"""
Clip Pusher - Continuously emits an HLS live stream from pre-generated chunks.
Uses ffmpeg concat demuxer for seamless chunk transitions, writing directly to
an HLS directory served by nginx. No RTMP/SRS in the path.
"""

import glob
import json
import os
import random
import re
import subprocess
import threading
import time
from typing import List, Optional, Tuple

STREAM_STATS_FILENAME = ".stream_stats.json"
CHUNKS_CREATED_FILENAME = ".chunks_created_total"
PLAY_COUNTS_FILENAME = ".play_counts.json"
LEGACY_CHUNK_SECONDS_ESTIMATE = 120.0
CONCAT_FILE_PATH = '/tmp/stream_concat.txt'

# ── Idle auto-pause ───────────────────────────────────────────────
# After this many seconds of no client activity (HLS playlist/segment
# requests pinged from nginx, or explicit /api/wake), ffmpeg is stopped
# to save CPU/GPU. Waking restarts the concat pass.
IDLE_TIMEOUT_SEC = int(os.getenv('IDLE_TIMEOUT_SEC', '300'))

# ── HLS output tuning ─────────────────────────────────────────────
HLS_SEGMENT_SECONDS = 6     # target segment duration
HLS_LIST_SIZE       = 30    # sliding window (~180s of live edge) — big buffer so skip/audio-skip gaps hide inside TV player buffer
HLS_PLAYLIST_NAME   = 'stream.m3u8'

# ── Output normalization ──────────────────────────────────────────
OUTPUT_AUDIO_RATE    = 44100
OUTPUT_AUDIO_CHANNELS = 2
OUTPUT_AUDIO_BITRATE = '128k'

# Audio extensions to scan for
AUDIO_EXTENSIONS = {'.mp3', '.aac', '.flac', '.ogg', '.wav', '.m4a'}


def _find_audio_files(audio_folder: str) -> List[str]:
    """Recursively find all audio files in the given folder."""
    files = []
    for ext in AUDIO_EXTENSIONS:
        files.extend(glob.glob(os.path.join(audio_folder, '**', f'*{ext}'), recursive=True))
        files.extend(glob.glob(os.path.join(audio_folder, '**', f'*{ext.upper()}'), recursive=True))
    return sorted(set(files))


class ClipPusher:
    """Emits a continuous HLS live stream from pre-generated video clips plus
    continuous background audio. Uses the ffmpeg concat demuxer to stitch
    chunks seamlessly within a pass and append_list+discont_start across
    restarts so TV clients keep polling the same m3u8 across skip/audio-skip."""

    def __init__(self, chunk_folder: str, hls_dir: str,
                 audio_folder: Optional[str] = None,
                 stats_dir: Optional[str] = None):
        self.chunk_folder    = chunk_folder
        self.hls_dir         = hls_dir
        self.audio_folder    = audio_folder
        self._stats_dir      = (stats_dir or chunk_folder).rstrip(os.sep)
        self._audio_files: List[str] = []
        # Shuffled play queue: every track gets played exactly once per cycle
        # before any repeats. Refilled (re-shuffled) once exhausted. This is
        # how music players “shuffle” — fair to short and long tracks alike,
        # unlike a least-total-seconds metric which over-picks short tracks.
        self._audio_queue: List[str] = []

        self._thread: Optional[threading.Thread] = None
        self._running = False
        self._current_chunk  = None
        self._current_chunk_started_at: Optional[float] = None
        self._current_chunk_duration: Optional[float] = None
        self._current_audio  = None
        self._persistent_audio_path: Optional[str] = None
        self._persistent_audio_duration: Optional[float] = None
        self._audio_position: float = 0.0
        self._chunks_pushed  = 0
        self._total_seconds_streamed: float = 0.0
        self._errors         = 0
        self._last_error: Optional[str] = None
        self._streamer_process: Optional[subprocess.Popen] = None
        self._play_chunk_next: Optional[str] = None
        self._play_chunk_lock = threading.Lock()

        # Idle auto-pause state. Start in paused mode so ffmpeg only spins
        # up once a client actually asks for the stream (via /api/wake or
        # an HLS request mirrored by nginx).
        self._last_activity_ts: float = time.time()
        self._paused: bool = True
        self._idle_timeout_sec: int = IDLE_TIMEOUT_SEC

        # Concat-pass state
        self._pass_chunks: List[Tuple[str, float]] = []      # [(path, duration), ...]
        self._pass_cumulative: List[float] = []               # [0, d0, d0+d1, ...]
        self._pass_start_time: Optional[float] = None
        self._interrupt_reason: Optional[str] = None          # 'skip', 'play_chunk', 'audio_skip'
        self._interrupt_lock = threading.Lock()

        # Systemic-failure detection: count consecutive loop iterations where
        # we saw chunks on disk but none validated. This catches silent bugs
        # (e.g. broken ffprobe) that would otherwise leave us idle forever.
        self._consecutive_empty_validations = 0

        self._load_stream_stats()

        # Scan audio folder on init
        if self.audio_folder and os.path.isdir(self.audio_folder):
            self._audio_files = _find_audio_files(self.audio_folder)
            if self._audio_files:
                print(f"Found {len(self._audio_files)} audio file(s) in {self.audio_folder}")
            else:
                print(f"Warning: no audio files found in {self.audio_folder}")
        else:
            if self.audio_folder:
                print(f"Warning: audio folder not found: {self.audio_folder}")

    # ── Public API ────────────────────────────────────────────────

    def start(self):
        if self._running:
            print("Clip pusher already running")
            return
        try:
            os.makedirs(self.hls_dir, exist_ok=True)
        except OSError as e:
            print(f"Warning: could not create HLS dir {self.hls_dir}: {e}")
        self._running = True
        self._thread  = threading.Thread(target=self._push_loop,
                                         daemon=True, name="clip-pusher")
        self._thread.start()
        print(f"Clip pusher started → HLS {self.hls_dir}/{HLS_PLAYLIST_NAME}")

    def stop(self):
        self._running = False
        if self._streamer_process and self._streamer_process.poll() is None:
            try:
                self._streamer_process.terminate()
            except Exception:
                pass
            try:
                self._streamer_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._streamer_process.kill()
        if self._thread:
            self._thread.join(timeout=10)
        print("Clip pusher stopped")

    def _stream_stats_path(self) -> str:
        return os.path.join(self._stats_dir, STREAM_STATS_FILENAME)

    def _load_stream_stats(self) -> None:
        path = self._stream_stats_path()
        if os.path.isfile(path):
            try:
                with open(path, 'r') as f:
                    data = json.load(f)
                self._total_seconds_streamed = float(data.get('total_seconds_streamed', 0))
                self._chunks_pushed = int(data.get('chunks_pushed_total', 0))
            except (json.JSONDecodeError, OSError):
                pass

    def _save_stream_stats(self) -> None:
        path = self._stream_stats_path()
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'w') as f:
                json.dump({
                    'total_seconds_streamed': self._total_seconds_streamed,
                    'chunks_pushed_total': self._chunks_pushed,
                }, f)
        except OSError:
            pass

    def _read_chunks_created_total(self) -> Optional[int]:
        path = os.path.join(self._stats_dir, CHUNKS_CREATED_FILENAME)
        if not os.path.isfile(path):
            return None
        try:
            with open(path, 'r') as f:
                return int(f.read().strip())
        except (ValueError, OSError):
            return None

    def _play_counts_path(self) -> str:
        return os.path.join(self._stats_dir, PLAY_COUNTS_FILENAME)

    @staticmethod
    def _normalize_model_url(url: str) -> str:
        """Canonical form: https://www.<domain>/<path> — lowercase, no trailing slash/hash/query."""
        s = (url or '').strip()
        if not s:
            return s
        s = re.sub(r'^https?://', '', s)
        s = re.sub(r'^(ww+\.)', 'www.', s)  # fix typos like ww.
        if not s.startswith('www.'):
            s = 'www.' + s if '.' in s.split('/')[0] else s
        s = s.split('?')[0].split('#')[0].rstrip('/')
        return 'https://' + s.lower() if s else url

    def _load_play_counts(self) -> dict:
        path = self._play_counts_path()
        if os.path.isfile(path):
            try:
                with open(path, 'r') as f:
                    return json.load(f)
            except (json.JSONDecodeError, OSError):
                pass
        return {'models': {}, 'audio': {}}

    def _save_play_counts(self, data: dict) -> None:
        path = self._play_counts_path()
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'w') as f:
                json.dump(data, f, indent=2)
        except OSError:
            pass

    @staticmethod
    def _coerce_audio_entry(raw) -> dict:
        """Normalize audio stats to {\"seconds\": float, \"chunks\": int} (handles legacy int-only)."""
        if raw is None:
            return {'seconds': 0.0, 'chunks': 0}
        if isinstance(raw, (int, float)):
            c = max(0, int(raw))
            return {'seconds': float(c) * LEGACY_CHUNK_SECONDS_ESTIMATE, 'chunks': c}
        if isinstance(raw, dict):
            sec = float(raw.get('seconds', 0) or 0)
            ch = int(raw.get('chunks', 0) or 0)
            if sec == 0 and ch == 0 and 'count' in raw:
                c = max(0, int(raw.get('count', 0) or 0))
                return {'seconds': float(c) * LEGACY_CHUNK_SECONDS_ESTIMATE, 'chunks': c}
            return {'seconds': max(0.0, sec), 'chunks': max(0, ch)}
        return {'seconds': 0.0, 'chunks': 0}

    @staticmethod
    def _format_audio_stream_time(sec: float) -> str:
        s = int(round(max(0.0, sec)))
        h, r = divmod(s, 3600)
        m, s2 = divmod(r, 60)
        if h:
            return f'{h:d}:{m:02d}:{s2:02d}'
        return f'{m:d}:{s2:02d}'

    def _extract_video_id(self, path: str) -> Optional[str]:
        """Extract 11-char YouTube video ID from path.
        Supports Pinchflat format: 'Title [video_id].mp4' and TubeArchivist legacy: 'video_id.mp4'."""
        stem = os.path.splitext(os.path.basename(path))[0]
        # Pinchflat: "Title [video_id]"
        m = re.search(r'\[([a-zA-Z0-9_-]{11})\]', stem)
        if m:
            return m.group(1)
        # TubeArchivist legacy: stem IS the video_id
        if stem and len(stem) == 11 and stem.replace('-', '').replace('_', '').isalnum():
            return stem
        return None

    def _record_play_count(self, chunk_path: str, audio_name: Optional[str],
                           audio_streamed_sec: float = 0.0) -> None:
        """Record play count for models (from chunk meta) and audio (seconds streamed this chunk + chunk count)."""
        data = self._load_play_counts()
        models = data.get('models', {})
        audio = data.get('audio', {})

        meta_path = chunk_path.replace('.mp4', '.meta.json')
        if os.path.isfile(meta_path):
            try:
                with open(meta_path, 'r') as f:
                    meta = json.load(f)
                raw_sources = meta.get('source_videos') or []
                model_to_video = {}
                for item in raw_sources:
                    path = item.get('path') if isinstance(item, dict) else (item if isinstance(item, str) else None)
                    model = item.get('model') if isinstance(item, dict) else None
                    if path and model:
                        vid = self._extract_video_id(path)
                        if vid and model not in model_to_video:
                            model_to_video[model] = vid
                for raw_m in (meta.get('model_info') or []):
                    if raw_m:
                        m = self._normalize_model_url(raw_m)
                        vid = model_to_video.get(raw_m)
                        entry = models.get(m)
                        if isinstance(entry, dict):
                            entry['count'] = entry.get('count', 0) + 1
                            if vid and not entry.get('video_id'):
                                entry['video_id'] = vid
                        elif isinstance(entry, (int, float)):
                            models[m] = {'count': entry + 1, 'video_id': vid} if vid else entry + 1
                        else:
                            models[m] = {'count': 1, 'video_id': vid} if vid else 1
            except (json.JSONDecodeError, OSError):
                pass

        if audio_name:
            prev = audio.get(audio_name, {'seconds': 0.0, 'chunks': 0})
            entry = self._coerce_audio_entry(prev)
            entry['seconds'] = entry['seconds'] + max(0.0, float(audio_streamed_sec))
            entry['chunks'] = entry['chunks'] + 1
            audio[audio_name] = entry

        data['models'] = models
        data['audio'] = audio
        self._save_play_counts(data)

    def get_play_counts(self) -> dict:
        """Return top models and audio by play count, merging URL variants."""
        data = self._load_play_counts()
        models = data.get('models', {})
        audio = data.get('audio', {})

        merged = {}
        for url, entry in models.items():
            norm = self._normalize_model_url(url)
            count = entry.get('count', entry) if isinstance(entry, dict) else entry
            video_id = entry.get('video_id') if isinstance(entry, dict) else None
            thumbnail_url = entry.get('thumbnail_url') if isinstance(entry, dict) else None
            if norm in merged:
                merged[norm]['count'] += count
                if video_id and not merged[norm]['video_id']:
                    merged[norm]['video_id'] = video_id
                if thumbnail_url and not merged[norm]['thumbnail_url']:
                    merged[norm]['thumbnail_url'] = thumbnail_url
            else:
                merged[norm] = {'count': count, 'video_id': video_id, 'thumbnail_url': thumbnail_url}

        top_models = [(url, m['count'], m['video_id'], m['thumbnail_url']) for url, m in merged.items()]
        top_models.sort(key=lambda x: -x[1])
        audio_rows = []
        for name, raw in audio.items():
            e = self._coerce_audio_entry(raw)
            audio_rows.append({
                'name': name,
                'seconds': round(e['seconds'], 1),
                'chunks': e['chunks'],
                'time_display': self._format_audio_stream_time(e['seconds']),
            })
        audio_rows.sort(key=lambda x: -x['seconds'])
        return {'models': top_models, 'audio': audio_rows}

    def get_status(self) -> dict:
        hours_played = round(self._total_seconds_streamed / 3600, 2) if self._total_seconds_streamed else 0
        return {
            'running':                   self._running,
            'hls_dir':                   self.hls_dir,
            'hls_playlist':              os.path.join(self.hls_dir, HLS_PLAYLIST_NAME),
            'chunks_pushed':             self._chunks_pushed,
            'total_seconds_streamed':    round(self._total_seconds_streamed, 1),
            'hours_played':              hours_played,
            'chunks_created_total':      self._read_chunks_created_total(),
            'audio_files_found':        len(self._audio_files),
            'current_audio':             self._current_audio,
            'audio_position_sec':        round(self._audio_position, 1) if self._persistent_audio_duration else None,
            'audio_track_duration_sec':  round(self._persistent_audio_duration, 1) if self._persistent_audio_duration else None,
            'errors':                    self._errors,
            'last_error':                self._last_error,
            'current_chunk':             self._current_chunk,
            'current_chunk_started_at': self._current_chunk_started_at,
            'current_chunk_duration':    self._current_chunk_duration,
        }

    def skip_to_next(self) -> bool:
        """Stop the current concat pass so the loop reshuffles and starts fresh."""
        with self._interrupt_lock:
            self._interrupt_reason = 'skip'
        return self._terminate_streamer()

    def skip_to_next_audio(self) -> bool:
        """Stop current stream and switch to the next audio track."""
        if self._audio_files:
            next_audio = self._get_next_audio(exclude_basename=self._current_audio)
            self._persistent_audio_path = next_audio
            self._audio_position = 0.0
            if self._persistent_audio_path:
                self._persistent_audio_duration = self._probe_duration(self._persistent_audio_path) or 3600.0
                self._current_audio = os.path.basename(self._persistent_audio_path)
            else:
                self._persistent_audio_duration = None
                self._current_audio = None
        with self._interrupt_lock:
            self._interrupt_reason = 'audio_skip'
        return self._terminate_streamer()

    def play_chunk(self, chunk_name: str) -> bool:
        """Queue a specific chunk to play next. Restarts the stream."""
        base = os.path.basename(chunk_name)
        if not base.endswith('.mp4'):
            return False
        path = os.path.join(self.chunk_folder, base)
        if not os.path.isfile(path):
            return False
        with self._play_chunk_lock:
            self._play_chunk_next = base
        with self._interrupt_lock:
            self._interrupt_reason = 'play_chunk'
        self._terminate_streamer()
        return True

    def play_audio(self, audio_name: str) -> bool:
        """Switch to a specific audio track."""
        if not self._audio_files:
            return False
        name = os.path.basename(audio_name)
        match = next((p for p in self._audio_files if os.path.basename(p) == name), None)
        if not match or not os.path.isfile(match):
            return False
        self._persistent_audio_path = match
        self._current_audio = os.path.basename(match)
        self._audio_position = 0.0
        self._persistent_audio_duration = self._probe_duration(match) or 3600.0
        with self._interrupt_lock:
            self._interrupt_reason = 'audio_skip'
        self._terminate_streamer()
        return True

    def _terminate_streamer(self) -> bool:
        """Terminate the running ffmpeg process. Returns True if a process was running."""
        proc = self._streamer_process
        if proc and proc.poll() is None:
            try:
                proc.terminate()
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
            except Exception:
                pass
            return True
        return False

    # ── Idle pause / wake ─────────────────────────────────────────

    def mark_activity(self) -> None:
        """Record a client interaction. Refreshes the idle timer; does NOT
        unpause (use wake() for that). Called from nginx-mirrored HLS
        requests on every playlist/segment fetch."""
        self._last_activity_ts = time.time()

    def wake(self) -> dict:
        """Explicit wake. Marks activity AND clears the paused flag so the
        push loop restarts ffmpeg. Idempotent — safe to call repeatedly."""
        was_paused = self._paused
        self._last_activity_ts = time.time()
        self._paused = False
        if was_paused:
            print("Stream wake requested — resuming ffmpeg")
        return {
            'paused': False,
            'was_paused': was_paused,
            'last_activity_ts': self._last_activity_ts,
        }

    def get_idle_status(self) -> dict:
        idle_sec = time.time() - self._last_activity_ts
        return {
            'paused': self._paused,
            'idle_seconds': round(idle_sec, 1),
            'idle_timeout_sec': self._idle_timeout_sec,
            'seconds_until_pause': max(0, round(self._idle_timeout_sec - idle_sec, 1)) if not self._paused else 0,
        }
    # ── Internal ──────────────────────────────────────────────────

    @staticmethod
    def _probe_duration(path: str) -> Optional[float]:
        """Get media duration in seconds via ffprobe. Returns None on failure."""
        try:
            out = subprocess.check_output(
                ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                 '-of', 'default=noprint_wrappers=1:nokey=1', path],
                stderr=subprocess.DEVNULL, timeout=10
            )
            return float(out.decode('utf-8').strip())
        except Exception:
            return None

    @staticmethod
    def _validate_chunk(path: str) -> Tuple[bool, float]:
        """Check chunk has a video stream and return its duration. Returns (valid, duration_sec)."""
        try:
            out = subprocess.check_output(
                ['ffprobe', '-v', 'error',
                 '-select_streams', 'v:0',
                 '-show_entries', 'stream=codec_type',
                 '-show_entries', 'format=duration',
                 '-of', 'json', path],
                stderr=subprocess.DEVNULL, timeout=10
            )
            data = json.loads(out.decode('utf-8'))
            streams = data.get('streams', [])
            if not streams or streams[0].get('codec_type') != 'video':
                return False, 0.0
            dur = float(data.get('format', {}).get('duration', 0))
            return dur > 0, dur
        except Exception:
            return False, 0.0

    def _audio_play_count(self, basename: str) -> float:
        """Fairness weight = total seconds streamed."""
        data = self._load_play_counts()
        audio = data.get('audio', {})
        raw = audio.get(basename, 0)
        return float(self._coerce_audio_entry(raw)['seconds'])

    def _pick_audio_least_played(self, pool: List[str]) -> Optional[str]:
        """Pick a file from pool with minimum recorded play count; random tie-break.

        Kept for backward compatibility / stats display. Not used for the
        next-track decision anymore — see _get_next_audio for the fair
        round-robin shuffle queue.
        """
        if not pool:
            return None
        scores = [(self._audio_play_count(os.path.basename(p)), p) for p in pool]
        min_score = min(s for s, _ in scores)
        candidates = [p for s, p in scores if s == min_score]
        chosen = random.choice(candidates)
        self._current_audio = os.path.basename(chosen)
        return chosen

    def _refill_audio_queue(self, avoid_first: Optional[str] = None) -> None:
        """Reshuffle all audio files into the play queue. Optionally make sure
        the just-played track isn't the first in the new cycle (so we don't
        get track A immediately followed by track A again across cycles)."""
        if not self._audio_files:
            self._audio_queue = []
            return
        queue = list(self._audio_files)
        random.shuffle(queue)
        if (avoid_first and len(queue) > 1
                and os.path.basename(queue[0]) == avoid_first):
            # Swap with a random later position to avoid back-to-back repeat.
            swap_idx = random.randrange(1, len(queue))
            queue[0], queue[swap_idx] = queue[swap_idx], queue[0]
        self._audio_queue = queue

    def _get_next_audio(self, exclude_basename: Optional[str] = None) -> Optional[str]:
        """Pop the next track off the shuffled queue. Refills the queue with a
        fresh shuffle once exhausted, so every audio file plays exactly once
        per cycle before any repeats. Length-fair: short and long tracks are
        selected with equal probability per cycle.
        """
        if not self._audio_files:
            return None
        # Drop any queue entries for files no longer on disk (rare, e.g.
        # operator removed a file mid-cycle).
        self._audio_queue = [p for p in self._audio_queue if p in self._audio_files]
        if not self._audio_queue:
            self._refill_audio_queue(avoid_first=exclude_basename)
        # If the front of the queue is the track we want to skip past (e.g.
        # user pressed audio-skip while it was playing), rotate it to the
        # back so it still plays this cycle, just later.
        if (exclude_basename
                and len(self._audio_queue) > 1
                and os.path.basename(self._audio_queue[0]) == exclude_basename):
            self._audio_queue.append(self._audio_queue.pop(0))
        chosen = self._audio_queue.pop(0)
        self._current_audio = os.path.basename(chosen)
        return chosen

    def _rotate_audio_after_full_chunk_round(self) -> None:
        """After a full shuffle pass, switch to another least-played track."""
        if not self._audio_files:
            return
        cur = os.path.basename(self._persistent_audio_path) if self._persistent_audio_path else None
        nxt = self._get_next_audio(exclude_basename=cur)
        if not nxt:
            return
        self._persistent_audio_path = nxt
        self._current_audio = os.path.basename(nxt)
        self._audio_position = 0.0
        self._persistent_audio_duration = self._probe_duration(nxt) or 3600.0

    def _write_concat_file(self, chunk_paths: List[str]) -> str:
        """Write ffmpeg concat demuxer file. Returns path."""
        with open(CONCAT_FILE_PATH, 'w') as f:
            for path in chunk_paths:
                safe = path.replace("'", "'\\''")
                f.write(f"file '{safe}'\n")
        return CONCAT_FILE_PATH

    def _build_concat_cmd(self, concat_path: str, audio_file: Optional[str],
                          audio_seek: float) -> List[str]:
        """Build ffmpeg command that writes an HLS live stream directly to the
        shared hls_dir. Uses append_list + discont_start so restarts (skip,
        audio_skip, play_chunk, pass-rollover) append to the same playlist and
        insert a discontinuity tag rather than ending the stream."""
        cmd = [
            'ffmpeg', '-y',
            '-hide_banner', '-nostats', '-loglevel', 'warning',
            '-re',
            '-f', 'concat', '-safe', '0',
            '-i', concat_path,
        ]
        if audio_file:
            if audio_seek > 0.01:
                cmd.extend(['-ss', str(round(audio_seek, 2))])
            cmd.extend(['-stream_loop', '-1', '-i', audio_file])
            cmd.extend(['-map', '0:v:0', '-map', '1:a:0'])
        else:
            cmd.extend([
                '-f', 'lavfi',
                '-i', f'anullsrc=channel_layout=stereo:sample_rate={OUTPUT_AUDIO_RATE}',
            ])
            cmd.extend(['-map', '0:v:0', '-map', '1:a:0'])

        playlist = os.path.join(self.hls_dir, HLS_PLAYLIST_NAME)
        segment_pattern = os.path.join(self.hls_dir, 'seg%d.ts')

        cmd.extend([
            '-c:v', 'copy',
            '-c:a', 'aac',
            '-ar', str(OUTPUT_AUDIO_RATE),
            '-ac', str(OUTPUT_AUDIO_CHANNELS),
            '-b:a', OUTPUT_AUDIO_BITRATE,
            '-shortest',
            '-fflags', '+genpts',
            '-f', 'hls',
            '-hls_time', str(HLS_SEGMENT_SECONDS),
            '-hls_list_size', str(HLS_LIST_SIZE),
            '-hls_flags', 'append_list+delete_segments+omit_endlist+independent_segments+discont_start+program_date_time+temp_file',
            '-hls_segment_type', 'mpegts',
            '-hls_allow_cache', '0',
            '-hls_start_number_source', 'datetime',
            '-hls_segment_filename', segment_pattern,
            playlist,
        ])
        return cmd

    def _chunk_index_at(self, elapsed: float) -> int:
        """Given elapsed seconds, return index into current pass chunks."""
        for i in range(len(self._pass_cumulative) - 1):
            if elapsed < self._pass_cumulative[i + 1]:
                return i
        return max(0, len(self._pass_chunks) - 1)

    def _ensure_audio(self) -> None:
        """Ensure an audio track is selected; pick one if needed."""
        if not self._audio_files:
            return
        if self._persistent_audio_path and os.path.isfile(self._persistent_audio_path):
            return
        self._persistent_audio_path = self._get_next_audio(exclude_basename=None)
        self._current_audio = os.path.basename(self._persistent_audio_path) if self._persistent_audio_path else None
        self._audio_position = 0.0
        if self._persistent_audio_path:
            self._persistent_audio_duration = self._probe_duration(self._persistent_audio_path) or 3600.0

    def _push_loop(self):
        print("Clip pusher control loop started (HLS output)")
        time.sleep(3)

        while self._running:
            # Idle pause: if no client has touched the stream in a while,
            # don't spin up ffmpeg — sit here and wait for a wake() or an
            # nginx-mirrored HLS ping. Cheap busy-wait at 1Hz.
            if self._paused:
                time.sleep(1)
                continue

            # Scan and validate chunks
            raw_chunks = sorted([
                os.path.join(self.chunk_folder, f)
                for f in os.listdir(self.chunk_folder)
                if f.endswith('.mp4') and not f.startswith('chunk_temp')
            ])
            if not raw_chunks:
                print(f"No chunks in {self.chunk_folder}. Waiting...")
                time.sleep(10)
                continue

            # Validate chunks (check video stream exists, get durations)
            valid_chunks: List[str] = []
            durations: List[float] = []
            for chunk in raw_chunks:
                ok, dur = self._validate_chunk(chunk)
                if ok and dur > 0:
                    valid_chunks.append(chunk)
                    durations.append(dur)
                else:
                    print(f"Skipping invalid chunk: {os.path.basename(chunk)}")

            if not valid_chunks:
                # Systemic-failure guard: if we saw raw chunks on disk but NONE
                # validated for multiple consecutive cycles, something is
                # broken upstream of chunks (e.g. ffprobe in the container).
                # Sitting idle here is the exact failure mode that left the
                # stream stale for 2 days on 2026-04-18. Exit loudly so the
                # kubelet restarts the pod and the liveness probe flags it.
                self._consecutive_empty_validations += 1
                print(
                    f"No valid chunks. raw_chunks={len(raw_chunks)} "
                    f"empty_cycles={self._consecutive_empty_validations}"
                )
                if (len(raw_chunks) >= 10
                        and self._consecutive_empty_validations >= 3):
                    msg = (
                        f"FATAL: {len(raw_chunks)} raw chunks on disk but "
                        f"0 validated for {self._consecutive_empty_validations} "
                        f"consecutive cycles — likely broken ffprobe or "
                        f"systemic chunk corruption. Exiting so kubelet "
                        f"can restart the pod."
                    )
                    print(msg, flush=True)
                    # Exit the whole process (not just the thread) so the
                    # liveness probe / kubelet handles recovery.
                    os._exit(42)
                time.sleep(10)
                continue

            # Reset the counter — we have valid chunks again.
            self._consecutive_empty_validations = 0

            # Shuffle
            combined = list(zip(valid_chunks, durations))
            random.shuffle(combined)
            valid_chunks, durations = [list(x) for x in zip(*combined)]

            # Handle queued play_chunk — put it first
            with self._play_chunk_lock:
                next_name = self._play_chunk_next
                if next_name:
                    self._play_chunk_next = None
                    full = os.path.join(self.chunk_folder, next_name)
                    for i, c in enumerate(valid_chunks):
                        if c == full:
                            valid_chunks.pop(i)
                            durations.pop(i)
                            break
                    ok, dur = self._validate_chunk(full)
                    if ok and dur > 0:
                        valid_chunks.insert(0, full)
                        durations.insert(0, dur)

            # Ensure audio is ready
            self._ensure_audio()

            # Build cumulative timeline
            cumulative = [0.0]
            for d in durations:
                cumulative.append(cumulative[-1] + d)
            total_duration = cumulative[-1]

            self._pass_chunks = list(zip(valid_chunks, durations))
            self._pass_cumulative = cumulative

            # Clear any previous interrupt
            with self._interrupt_lock:
                self._interrupt_reason = None

            # Write concat file and build command
            concat_path = self._write_concat_file(valid_chunks)
            audio_file = self._persistent_audio_path
            audio_seek = self._audio_position
            cmd = self._build_concat_cmd(concat_path, audio_file, audio_seek)

            print(f"Starting concat pass: {len(valid_chunks)} chunks, ~{int(total_duration)}s total")
            if audio_file and audio_seek > 0:
                print(f"  Audio: {self._current_audio} from {audio_seek:.1f}s / {self._persistent_audio_duration:.1f}s")

            # Launch ffmpeg.
            # IMPORTANT: stderr MUST NOT be subprocess.PIPE here — we don't drain it while
            # ffmpeg runs, and the 64KB pipe buffer fills up on long sessions (-loglevel
            # warning emits on every concat boundary), causing ffmpeg to block on write
            # indefinitely. That manifests as ffmpeg alive at 0% CPU with SRS seeing no
            # publisher (the exact symptom we hit). Use DEVNULL.
            self._pass_start_time = time.time()
            self._streamer_process = subprocess.Popen(
                cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )

            prev_chunk_idx = -1
            last_stats_save = time.time()
            # Watchdog: if chunk_idx doesn't advance for this many seconds past the
            # expected chunk duration, ffmpeg is stalled — kill it and restart the pass.
            STALL_GRACE = 120  # seconds
            last_progress_time = time.time()

            while self._running and self._streamer_process.poll() is None:
                elapsed = time.time() - self._pass_start_time
                chunk_idx = self._chunk_index_at(elapsed)

                # Record play counts when crossing chunk boundaries
                if chunk_idx > prev_chunk_idx and prev_chunk_idx >= 0:
                    for ci in range(prev_chunk_idx, min(chunk_idx, len(self._pass_chunks))):
                        p, d = self._pass_chunks[ci]
                        self._chunks_pushed += 1
                        self._total_seconds_streamed += d
                        self._record_play_count(p, self._current_audio, d)
                    last_progress_time = time.time()
                prev_chunk_idx = chunk_idx

                # Stall watchdog: if we haven't crossed a chunk boundary in
                # (current_chunk_duration + STALL_GRACE) seconds, ffmpeg is hung.
                if chunk_idx < len(self._pass_chunks):
                    expected_dur = self._pass_chunks[chunk_idx][1]
                    if time.time() - last_progress_time > expected_dur + STALL_GRACE:
                        print(f"Stream stalled (no progress in {int(time.time() - last_progress_time)}s on chunk {chunk_idx}); killing ffmpeg")
                        self._errors += 1
                        self._last_error = "stall watchdog triggered"
                        self._terminate_streamer()
                        break

                # Update current-chunk state
                if chunk_idx < len(self._pass_chunks):
                    p, d = self._pass_chunks[chunk_idx]
                    self._current_chunk = os.path.basename(p)
                    self._current_chunk_started_at = self._pass_start_time + self._pass_cumulative[chunk_idx]
                    self._current_chunk_duration = d

                # Update audio position for status display
                if self._persistent_audio_duration and self._persistent_audio_duration > 0:
                    self._audio_position = (audio_seek + elapsed) % self._persistent_audio_duration

                # Save stats periodically
                now = time.time()
                if now - last_stats_save >= 30:
                    self._save_stream_stats()
                    last_stats_save = now

                # Check for interrupts
                with self._interrupt_lock:
                    if self._interrupt_reason:
                        break

                # Idle auto-pause: stop ffmpeg if no client activity recently.
                if (time.time() - self._last_activity_ts) > self._idle_timeout_sec:
                    print(
                        f"Idle timeout: no client activity for "
                        f"{int(time.time() - self._last_activity_ts)}s — pausing stream"
                    )
                    self._paused = True
                    self._terminate_streamer()
                    break

                time.sleep(1)

            # ── Post-process ──
            actual_elapsed = time.time() - self._pass_start_time

            # Update audio position
            if self._persistent_audio_duration and self._persistent_audio_duration > 0:
                self._audio_position = (audio_seek + actual_elapsed) % self._persistent_audio_duration

            # Record stats for the last chunk that was playing
            chunk_idx = self._chunk_index_at(actual_elapsed)
            if chunk_idx >= 0 and chunk_idx < len(self._pass_chunks):
                p, d = self._pass_chunks[chunk_idx]
                chunk_elapsed = actual_elapsed - self._pass_cumulative[chunk_idx]
                self._chunks_pushed += 1
                self._total_seconds_streamed += max(0, min(chunk_elapsed, d))
                self._record_play_count(p, self._current_audio, max(0, min(chunk_elapsed, d)))
            # Also record any fully-completed chunks between prev_chunk_idx and chunk_idx
            if prev_chunk_idx >= 0 and chunk_idx > prev_chunk_idx:
                for ci in range(prev_chunk_idx, min(chunk_idx, len(self._pass_chunks))):
                    cp, cd = self._pass_chunks[ci]
                    self._chunks_pushed += 1
                    self._total_seconds_streamed += cd
                    self._record_play_count(cp, self._current_audio, cd)

            self._save_stream_stats()

            rc = self._streamer_process.returncode if self._streamer_process else None
            if rc is not None and rc != 0:
                print(f"Concat pass ended with code {rc}")
                self._errors += 1
                self._last_error = f"ffmpeg exit {rc}"

            # Cleanup
            if self._streamer_process and self._streamer_process.poll() is None:
                self._terminate_streamer()

            # Handle interrupt or completion
            with self._interrupt_lock:
                reason = self._interrupt_reason
                self._interrupt_reason = None

            if reason in ('skip', 'play_chunk', 'audio_skip'):
                time.sleep(0.3)
            elif reason is None and self._running:
                # Full pass completed — rotate audio for next pass
                if self._audio_files:
                    self._rotate_audio_after_full_chunk_round()
                time.sleep(0.5)
            else:
                time.sleep(3)

        print("Clip pusher loop ended")
