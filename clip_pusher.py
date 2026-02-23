"""
Clip Pusher - Continuously pushes pre-generated chunks to RTMP server
Creates a never-ending live stream from pre-generated video chunks with continuous background audio.
"""

import glob
import os
import random
import subprocess
import threading
import time
from typing import List, Optional

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
                 audio_folder: Optional[str] = None):
        self.chunk_folder    = chunk_folder
        self.rtmp_url        = rtmp_url
        self.audio_folder    = audio_folder
        self._audio_files: List[str] = []

        self._thread: Optional[threading.Thread] = None
        self._running = False
        self._current_chunk  = None
        self._current_audio  = None
        self._chunks_pushed  = 0
        self._errors         = 0
        self._last_error: Optional[str] = None
        self._streamer_process: Optional[subprocess.Popen] = None

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

    def get_status(self) -> dict:
        return {
            'running':           self._running,
            'rtmp_url':          self.rtmp_url,
            'chunks_pushed':     self._chunks_pushed,
            'audio_files_found': len(self._audio_files),
            'current_audio':     self._current_audio,
            'errors':            self._errors,
            'last_error':        self._last_error,
            'current_chunk':     self._current_chunk,
        }

    # ── Internal ──────────────────────────────────────────────────

    def _get_audio_file(self) -> Optional[str]:
        """Get a random audio file for background music."""
        if not self._audio_files:
            return None
        audio = random.choice(self._audio_files)
        self._current_audio = os.path.basename(audio)
        return audio

    def _stream_chunk(self, chunk_path: str):
        """
        Stream a single chunk to RTMP with background audio.
        Since the chunks are pre-normalized, we can use -c:v copy.
        """
        audio_file = self._get_audio_file()

        cmd = [
            'ffmpeg', '-y', 
            '-hide_banner', '-nostats', '-loglevel', 'warning',
            
            # ── Video chunk input ──
            '-re',                      # real-time pacing
            '-i', chunk_path,
        ]

        # ── Audio input ──
        if audio_file:
            cmd.extend([
                '-stream_loop', '-1',   # loop audio forever alongside video
                '-i', audio_file,
            ])
            map_args = ['-map', '0:v:0', '-map', '1:a:0']
        else:
            # Silent audio fallback
            cmd.extend([
                '-f', 'lavfi',
                '-i', f'anullsrc=channel_layout=stereo:sample_rate={OUTPUT_AUDIO_RATE}',
            ])
            map_args = ['-map', '0:v:0', '-map', '1:a:0']
            
        # Determine chunk duration to stop audio properly
        duration_cmd = ['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', chunk_path]
        try:
            chunk_duration = float(subprocess.check_output(duration_cmd).decode('utf-8').strip())
            # Add a tiny buffer so it definitely reaches the end of the video
            chunk_duration += 0.5
        except Exception:
            chunk_duration = 300 # Fallback 5 mins

        cmd.extend([
            *map_args,
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

        print(f"Streaming chunk: {os.path.basename(chunk_path)} → {self.rtmp_url}")
        
        self._streamer_process = subprocess.Popen(
            cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

        while self._running and self._streamer_process.poll() is None:
            time.sleep(1)
            
        if self._running and self._streamer_process.poll() is not None:
            if self._streamer_process.returncode != 0:
                print(f"Streamer process exited with code {self._streamer_process.returncode}")
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
            
            for chunk in chunks:
                if not self._running:
                    break
                
                self._current_chunk = os.path.basename(chunk)
                try:
                    self._stream_chunk(chunk)
                except Exception as exc:
                    self._last_error = str(exc)
                    self._errors += 1
                    print(f"Stream loop error: {exc}")
                    time.sleep(5)
                    
                # Cleanup process before next iteration
                if self._streamer_process and self._streamer_process.poll() is None:
                    self._streamer_process.terminate()
                    try:
                        self._streamer_process.wait(timeout=5)
                    except:
                        self._streamer_process.kill()

        print("Clip pusher loop ended")

