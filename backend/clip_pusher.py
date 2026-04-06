"""
Clip Pusher - Continuously pushes pre-generated chunks to RTMP server
Creates a never-ending live stream from pre-generated video chunks with continuous background audio.
"""

import glob
import json
import os
import random
import re
import subprocess
import threading
import time
from typing import List, Optional

STREAM_STATS_FILENAME = ".stream_stats.json"
CHUNKS_CREATED_FILENAME = ".chunks_created_total"
PLAY_COUNTS_FILENAME = ".play_counts.json"
# Legacy stats stored only chunk counts; convert to estimated seconds for fairness until real seconds accrue.
LEGACY_CHUNK_SECONDS_ESTIMATE = 120.0

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
    """Pushes random video clips + continuous background audio to RTMP."""

    def __init__(self, chunk_folder: str, rtmp_url: str,
                 audio_folder: Optional[str] = None,
                 stats_dir: Optional[str] = None):
        self.chunk_folder    = chunk_folder
        self.rtmp_url        = rtmp_url
        self.audio_folder    = audio_folder
        # Persistent stats (hours played, chunks pushed/created) live here so they survive deployments
        self._stats_dir      = (stats_dir or chunk_folder).rstrip(os.sep)
        self._audio_files: List[str] = []

        self._thread: Optional[threading.Thread] = None
        self._running = False
        self._current_chunk  = None
        self._current_chunk_started_at: Optional[float] = None
        self._current_chunk_duration: Optional[float] = None
        self._current_audio  = None
        self._persistent_audio_path: Optional[str] = None  # same track across chunks
        self._persistent_audio_duration: Optional[float] = None  # seconds
        self._audio_position: float = 0.0  # position within track (0..duration), so next chunk continues from here
        self._chunks_pushed  = 0
        self._total_seconds_streamed: float = 0.0  # persisted, survives restarts
        self._errors         = 0
        self._last_error: Optional[str] = None
        self._streamer_process: Optional[subprocess.Popen] = None
        self._play_chunk_next: Optional[str] = None
        self._play_chunk_lock = threading.Lock()
        # When skip_to_next() runs, it already advances _audio_position; post-_stream_chunk must not add again.
        self._audio_advance_done_for_this_chunk: bool = False

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
        self._running = True
        self._thread  = threading.Thread(target=self._push_loop,
                                         daemon=True, name="clip-pusher")
        self._thread.start()
        print(f"Clip pusher started → {self.rtmp_url}")

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
            'rtmp_url':                  self.rtmp_url,
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
        """Stop the current chunk so the loop advances to the next one. Returns True if a stream was running."""
        if self._streamer_process and self._streamer_process.poll() is None:
            # Advance audio position by how long this chunk actually played, so next chunk continues from there.
            # Only set the flag when we applied it here — otherwise post-_stream_chunk still advances once.
            self._audio_advance_done_for_this_chunk = False
            if self._current_chunk_started_at and self._persistent_audio_duration and self._persistent_audio_duration > 0:
                actual = time.time() - self._current_chunk_started_at
                self._audio_position = (self._audio_position + actual) % self._persistent_audio_duration
                self._audio_advance_done_for_this_chunk = True
            try:
                self._streamer_process.terminate()
                self._streamer_process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self._streamer_process.kill()
            except Exception:
                pass
            return True
        return False

    def skip_to_next_audio(self) -> bool:
        """Stop current stream and switch to the next audio track. Returns True if a stream was running."""
        if self._streamer_process and self._streamer_process.poll() is None:
            # Pre-select next audio before terminating so status/refresh shows it immediately
            if self._audio_files:
                # Least-played among tracks other than current (fair rotation).
                next_audio = self._get_next_audio(exclude_basename=self._current_audio)
                self._persistent_audio_path = next_audio
                self._audio_position = 0.0
                if self._persistent_audio_path:
                    try:
                        out = subprocess.check_output(
                            ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                             '-of', 'default=noprint_wrappers=1:nokey=1', self._persistent_audio_path]
                        )
                        self._persistent_audio_duration = float(out.decode('utf-8').strip())
                    except Exception:
                        self._persistent_audio_duration = 3600.0
                else:
                    self._persistent_audio_duration = None
            else:
                self._persistent_audio_path = None
                self._current_audio = None
            try:
                self._streamer_process.terminate()
                self._streamer_process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self._streamer_process.kill()
            except Exception:
                pass
            return True
        return False

    def play_chunk(self, chunk_name: str) -> bool:
        """Queue a specific chunk to play next in the stream. Stops current chunk if running."""
        base = os.path.basename(chunk_name)
        if not base.endswith('.mp4'):
            return False
        path = os.path.join(self.chunk_folder, base)
        if not os.path.isfile(path):
            return False
        with self._play_chunk_lock:
            self._play_chunk_next = base
        self.skip_to_next()
        return True

    def play_audio(self, audio_name: str) -> bool:
        """Switch to a specific audio track. Stops current stream and restarts with the new track."""
        if not self._audio_files:
            return False
        name = os.path.basename(audio_name)
        match = next((p for p in self._audio_files if os.path.basename(p) == name), None)
        if not match or not os.path.isfile(match):
            return False
        self._persistent_audio_path = match
        self._current_audio = os.path.basename(match)
        self._audio_position = 0.0
        try:
            out = subprocess.check_output(
                ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                 '-of', 'default=noprint_wrappers=1:nokey=1', match]
            )
            self._persistent_audio_duration = float(out.decode('utf-8').strip())
        except Exception:
            self._persistent_audio_duration = 3600.0
        if self._streamer_process and self._streamer_process.poll() is None:
            try:
                self._streamer_process.terminate()
                self._streamer_process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self._streamer_process.kill()
            except Exception:
                pass
            return True
        return True

    # ── Internal ──────────────────────────────────────────────────

    def _audio_play_count(self, basename: str) -> float:
        """Fairness weight = total seconds streamed (legacy int entries estimated as chunks * avg length)."""
        data = self._load_play_counts()
        audio = data.get('audio', {})
        raw = audio.get(basename, 0)
        return float(self._coerce_audio_entry(raw)['seconds'])

    def _pick_audio_least_played(self, pool: List[str]) -> Optional[str]:
        """Pick a file from pool with minimum recorded play count; random tie-break."""
        if not pool:
            return None
        scores = [(self._audio_play_count(os.path.basename(p)), p) for p in pool]
        min_score = min(s for s, _ in scores)
        candidates = [p for s, p in scores if s == min_score]
        chosen = random.choice(candidates)
        self._current_audio = os.path.basename(chosen)
        return chosen

    def _get_next_audio(self, exclude_basename: Optional[str] = None) -> Optional[str]:
        """Pick next track: least-played among library (or among pool excluding current)."""
        if not self._audio_files:
            return None
        pool = [p for p in self._audio_files if os.path.basename(p) != exclude_basename]
        if not pool:
            pool = list(self._audio_files)
        return self._pick_audio_least_played(pool)

    def _rotate_audio_after_full_chunk_round(self) -> None:
        """After playing a full shuffled pass (no push-chunk break), switch to another least-played track."""
        if not self._audio_files:
            return
        cur = os.path.basename(self._persistent_audio_path) if self._persistent_audio_path else None
        nxt = self._get_next_audio(exclude_basename=cur)
        if not nxt:
            return
        self._persistent_audio_path = nxt
        self._current_audio = os.path.basename(nxt)
        self._audio_position = 0.0
        try:
            out = subprocess.check_output(
                ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                 '-of', 'default=noprint_wrappers=1:nokey=1', nxt]
            )
            self._persistent_audio_duration = float(out.decode('utf-8').strip())
        except Exception:
            self._persistent_audio_duration = 3600.0

    def _stream_chunk(self, chunk_path: str, audio_start_sec: float = 0.0):
        """
        Stream a single chunk to RTMP with background audio.
        audio_start_sec = position in track so playback continues across chunks.
        We use concat filter: [audio from start_sec to end] + [audio looped from 0] so the seek is respected.
        """
        audio_file = self._persistent_audio_path
        seek_sec = round(audio_start_sec, 2) if audio_start_sec > 0.01 else 0.0

        cmd = [
            'ffmpeg', '-y',
            '-hide_banner', '-nostats', '-loglevel', 'warning',

            # Input 0: video chunk
            '-re',
            '-i', chunk_path,
        ]

        if audio_file:
            # Input 1: audio from seek_sec to end (once). Input 2: same file looped from 0.
            # Concat gives: [position..end] then [0..end, 0..end, ...] = continuous from position.
            if seek_sec > 0:
                cmd.extend([
                    '-ss', str(seek_sec),
                    '-i', audio_file,
                    '-stream_loop', '-1',
                    '-i', audio_file,
                ])
                # [1:a] = tail from seek, [2:a] = full loop; concat so we start at position then loop
                cmd.extend([
                    '-filter_complex', '[1:a][2:a]concat=n=2:v=0:a=1[a]',
                    '-map', '0:v:0', '-map', '[a]',
                ])
            else:
                cmd.extend([
                    '-stream_loop', '-1',
                    '-i', audio_file,
                ])
                cmd.extend(['-map', '0:v:0', '-map', '1:a:0'])
        else:
            cmd.extend([
                '-f', 'lavfi',
                '-i', f'anullsrc=channel_layout=stereo:sample_rate={OUTPUT_AUDIO_RATE}',
            ])
            cmd.extend(['-map', '0:v:0', '-map', '1:a:0'])
            
        # Determine chunk duration to stop audio properly
        duration_cmd = ['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', chunk_path]
        try:
            chunk_duration = float(subprocess.check_output(duration_cmd).decode('utf-8').strip())
            # Add a tiny buffer so it definitely reaches the end of the video.
            # Important: we must advance _audio_position using the same duration we ask ffmpeg to run.
            chunk_duration += 0.5
            self._current_chunk_duration = chunk_duration
        except Exception:
            # Fallback 5 mins (keep _current_chunk_duration consistent with ffmpeg -t)
            chunk_duration = 300.0
            chunk_duration += 0.5
            self._current_chunk_duration = chunk_duration

        cmd.extend([
            '-c:v', 'copy',             # remux H264 natively, zero CPU!
            '-c:a', 'aac',
            '-ar', str(OUTPUT_AUDIO_RATE),
            '-ac', str(OUTPUT_AUDIO_CHANNELS),
            '-b:a', OUTPUT_AUDIO_BITRATE,
            '-t', str(chunk_duration),  # Stop when chunk ends
            '-f', 'flv',
            '-flvflags', 'no_duration_filesize',
            self.rtmp_url,
        ])

        print(f"Streaming chunk: {os.path.basename(chunk_path)} → {self.rtmp_url}" + (f" (audio from {seek_sec}s)" if seek_sec > 0 and audio_file else ""))
        
        self._streamer_process = subprocess.Popen(
            cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
        )

        while self._running and self._streamer_process.poll() is None:
            time.sleep(1)

        stderr_out = None
        if self._streamer_process.stderr:
            try:
                stderr_out = self._streamer_process.stderr.read().decode('utf-8', errors='replace')
            except Exception:
                pass
            
        if self._running and self._streamer_process.poll() is not None:
            if self._streamer_process.returncode != 0:
                print(f"Streamer process exited with code {self._streamer_process.returncode}")
                if stderr_out:
                    print(f"ffmpeg stderr: {stderr_out[:500]}")
                self._errors += 1
            self._chunks_pushed += 1

    def _push_loop(self):
        print("Clip pusher control loop started")
        time.sleep(3)   # let nginx-rtmp warm up

        while self._running:
            chunks = sorted([
                os.path.join(self.chunk_folder, f)
                for f in os.listdir(self.chunk_folder)
                if f.endswith('.mp4') and not f.startswith('chunk_temp')
            ])
            
            if not chunks:
                print(f"No chunks found in {self.chunk_folder}. Waiting...")
                time.sleep(10)
                continue
                
            random.shuffle(chunks)

            with self._play_chunk_lock:
                next_name = self._play_chunk_next
                if next_name:
                    self._play_chunk_next = None
                    full = os.path.join(self.chunk_folder, next_name)
                    if full in chunks:
                        chunks.remove(full)
                        chunks.insert(0, full)

            # Pick one audio track for this pass; rotate to another least-played track after a full round
            # (not when user queued a chunk — that must keep the same track/position).
            if self._audio_files:
                if self._persistent_audio_path is None or not os.path.isfile(self._persistent_audio_path):
                    self._persistent_audio_path = self._get_next_audio(exclude_basename=None)
                    self._current_audio = os.path.basename(self._persistent_audio_path) if self._persistent_audio_path else None
                    self._audio_position = 0.0
                    if self._persistent_audio_path:
                        try:
                            out = subprocess.check_output(
                                ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                                 '-of', 'default=noprint_wrappers=1:nokey=1', self._persistent_audio_path]
                            )
                            self._persistent_audio_duration = float(out.decode('utf-8').strip())
                        except Exception as e:
                            self._persistent_audio_duration = 3600.0
                            print(f"Warning: ffprobe duration failed for {self._persistent_audio_path}: {e}. Using 3600s fallback.")

            broke_for_queued_chunk = False
            for chunk in chunks:
                if not self._running:
                    break

                self._current_chunk = os.path.basename(chunk)
                self._current_chunk_started_at = time.time()
                self._current_chunk_duration = None  # set in _stream_chunk after ffprobe
                self._audio_advance_done_for_this_chunk = False
                audio_start = self._audio_position
                if audio_start > 0 and self._persistent_audio_duration:
                    print(f"Resuming audio at {audio_start:.1f}s / {self._persistent_audio_duration:.1f}s")
                try:
                    self._stream_chunk(chunk, audio_start_sec=audio_start)
                except Exception as exc:
                    self._last_error = str(exc)
                    self._errors += 1
                    print(f"Stream loop error: {exc}")
                    time.sleep(5)
                # Advance audio timeline. If skip_to_next() ran, it already updated _audio_position — do not add again.
                skipped_audio_advance = self._audio_advance_done_for_this_chunk
                if skipped_audio_advance:
                    self._audio_advance_done_for_this_chunk = False
                    advance = time.time() - self._current_chunk_started_at
                elif self._current_chunk_duration is not None and self._streamer_process and self._streamer_process.returncode == 0:
                    advance = self._current_chunk_duration
                else:
                    advance = time.time() - self._current_chunk_started_at

                if self._persistent_audio_duration and self._persistent_audio_duration > 0 and not skipped_audio_advance:
                    self._audio_position = (self._audio_position + advance) % self._persistent_audio_duration

                self._total_seconds_streamed += advance
                self._save_stream_stats()
                self._record_play_count(chunk, self._current_audio, advance)

                # Cleanup process before next iteration
                if self._streamer_process and self._streamer_process.poll() is None:
                    self._streamer_process.terminate()
                    try:
                        self._streamer_process.wait(timeout=5)
                    except Exception:
                        self._streamer_process.kill()

                with self._play_chunk_lock:
                    if self._play_chunk_next:
                        broke_for_queued_chunk = True
                        break

            # Rotate track only after a full pass while still running (not mid-shutdown).
            if not broke_for_queued_chunk and self._running and self._audio_files:
                self._rotate_audio_after_full_chunk_round()

        print("Clip pusher loop ended")
