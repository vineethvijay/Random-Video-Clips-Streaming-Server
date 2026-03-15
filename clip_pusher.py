"""
Clip Pusher - Continuously pushes pre-generated chunks to RTMP server
Creates a never-ending live stream from pre-generated video chunks with continuous background audio.
"""

import glob
import json
import os
import random
import subprocess
import threading
import time
from typing import List, Optional

STREAM_STATS_FILENAME = ".stream_stats.json"
CHUNKS_CREATED_FILENAME = ".chunks_created_total"
PLAY_COUNTS_FILENAME = ".play_counts.json"
AUDIO_QUEUE_FILENAME = ".audio_queue.txt"

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
        self._audio_queue: List[str] = []

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

    def _extract_video_id(self, path: str) -> Optional[str]:
        """Extract 11-char YouTube video ID from path (e.g. .../UCxxx/abc123.mp4 -> abc123)."""
        stem = os.path.splitext(os.path.basename(path))[0]
        if stem and len(stem) == 11 and stem.replace('-', '').replace('_', '').isalnum():
            return stem
        return None

    def _record_play_count(self, chunk_path: str, audio_name: Optional[str]) -> None:
        """Record play count for models (from chunk meta) and audio (current track)."""
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
                model_to_thumbnail = {}
                fallback_vid = None
                for item in raw_sources:
                    path = item.get('path') if isinstance(item, dict) else (item if isinstance(item, str) else None)
                    model = item.get('model') if isinstance(item, dict) else None
                    thumb = item.get('thumbnail_url') if isinstance(item, dict) else None
                    if path:
                        vid = self._extract_video_id(path)
                        if vid:
                            if not fallback_vid:
                                fallback_vid = vid
                            if model and model not in model_to_video:
                                model_to_video[model] = vid
                            if model and model not in model_to_thumbnail:
                                model_to_thumbnail[model] = thumb or f"https://img.youtube.com/vi/{vid}/hqdefault.jpg"
                for m in (meta.get('model_info') or []):
                    if m:
                        vid = model_to_video.get(m) or fallback_vid
                        thumb = model_to_thumbnail.get(m)
                        entry = models.get(m)
                        if isinstance(entry, dict):
                            entry['count'] = entry.get('count', 0) + 1
                            if vid:
                                entry['video_id'] = vid
                            if thumb:
                                entry['thumbnail_url'] = thumb
                        elif isinstance(entry, (int, float)):
                            models[m] = {'count': entry + 1, 'video_id': vid, 'thumbnail_url': thumb} if (vid or thumb) else entry + 1
                        else:
                            models[m] = {'count': 1, 'video_id': vid, 'thumbnail_url': thumb} if (vid or thumb) else 1
            except (json.JSONDecodeError, OSError):
                pass

        if audio_name:
            audio[audio_name] = audio.get(audio_name, 0) + 1

        data['models'] = models
        data['audio'] = audio
        self._save_play_counts(data)

    def get_play_counts(self) -> dict:
        """Return top models and audio by play count."""
        data = self._load_play_counts()
        models = data.get('models', {})
        audio = data.get('audio', {})
        top_models = []
        for url, entry in models.items():
            count = entry.get('count', entry) if isinstance(entry, dict) else entry
            video_id = entry.get('video_id') if isinstance(entry, dict) else None
            thumbnail_url = entry.get('thumbnail_url') if isinstance(entry, dict) else None
            top_models.append((url, count, video_id, thumbnail_url))
        top_models.sort(key=lambda x: -x[1])
        top_models = top_models[:20]
        top_audio = sorted(audio.items(), key=lambda x: -x[1])[:20]
        return {'models': top_models, 'audio': top_audio}

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
            # Advance audio position by how long this chunk actually played, so next chunk continues from there
            if self._current_chunk_started_at and self._persistent_audio_duration and self._persistent_audio_duration > 0:
                actual = time.time() - self._current_chunk_started_at
                self._audio_position = (self._audio_position + actual) % self._persistent_audio_duration
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
                candidates = [f for f in self._audio_files if os.path.basename(f) != self._current_audio]
                pool = candidates if candidates else self._audio_files
                next_audio = random.choice(pool)
                self._persistent_audio_path = next_audio
                self._current_audio = os.path.basename(next_audio)
                self._audio_position = 0.0
                try:
                    out = subprocess.check_output(
                        ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                         '-of', 'default=noprint_wrappers=1:nokey=1', next_audio]
                    )
                    self._persistent_audio_duration = float(out.decode('utf-8').strip())
                except Exception:
                    self._persistent_audio_duration = 3600.0
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

    # ── Internal ──────────────────────────────────────────────────

    def _audio_queue_path(self) -> str:
        return os.path.join(self._stats_dir, AUDIO_QUEUE_FILENAME)

    def _load_audio_queue(self) -> List[str]:
        path = self._audio_queue_path()
        if os.path.isfile(path):
            try:
                with open(path, 'r') as f:
                    lines = [l.strip() for l in f if l.strip()]
                valid = [p for p in lines if os.path.isfile(p)]
                if valid:
                    return valid
            except OSError:
                pass
        return []

    def _save_audio_queue(self, queue: List[str]) -> None:
        path = self._audio_queue_path()
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'w') as f:
                f.write('\n'.join(queue))
        except OSError:
            pass

    def _get_next_audio(self) -> Optional[str]:
        """Get next audio from LRU queue (take from head, move to tail). Ensures fair rotation."""
        if not self._audio_files:
            return None
        if not self._audio_queue:
            self._audio_queue = self._load_audio_queue()
        valid = [p for p in self._audio_queue if os.path.isfile(p)]
        new_files = [p for p in self._audio_files if p not in valid]
        if not valid or new_files:
            valid = list(valid) + new_files
            random.shuffle(valid)
        if not valid:
            valid = list(self._audio_files)
            random.shuffle(valid)
        audio = valid.pop(0)
        valid.append(audio)
        self._audio_queue = valid
        self._save_audio_queue(valid)
        self._current_audio = os.path.basename(audio)
        return audio

    def _get_audio_file(self) -> Optional[str]:
        """Get a random audio file (used by skip_to_next_audio)."""
        if not self._audio_files:
            return None
        audio = random.choice(self._audio_files)
        self._current_audio = os.path.basename(audio)
        return audio

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
            self._current_chunk_duration = chunk_duration
            # Add a tiny buffer so it definitely reaches the end of the video
            chunk_duration += 0.5
        except Exception:
            chunk_duration = 300  # Fallback 5 mins
            self._current_chunk_duration = 300.0

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

            # Pick one audio track for the whole round (LRU queue for fair rotation when switching)
            if self._audio_files:
                if self._persistent_audio_path is None or not os.path.isfile(self._persistent_audio_path):
                    self._persistent_audio_path = self._get_next_audio()
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

            for chunk in chunks:
                if not self._running:
                    break

                self._current_chunk = os.path.basename(chunk)
                self._current_chunk_started_at = time.time()
                self._current_chunk_duration = None  # set in _stream_chunk after ffprobe
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
                # Advance by how much audio we actually output (chunk duration if it ran to completion, else wall clock)
                if self._current_chunk_duration is not None and self._streamer_process and self._streamer_process.returncode == 0:
                    advance = self._current_chunk_duration
                else:
                    advance = time.time() - self._current_chunk_started_at
                if self._persistent_audio_duration and self._persistent_audio_duration > 0:
                    self._audio_position = (self._audio_position + advance) % self._persistent_audio_duration
                self._total_seconds_streamed += advance
                self._save_stream_stats()
                self._record_play_count(chunk, self._current_audio)

                # Cleanup process before next iteration
                if self._streamer_process and self._streamer_process.poll() is None:
                    self._streamer_process.terminate()
                    try:
                        self._streamer_process.wait(timeout=5)
                    except:
                        self._streamer_process.kill()

                with self._play_chunk_lock:
                    if self._play_chunk_next:
                        break

        print("Clip pusher loop ended")

