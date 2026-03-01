#!/usr/bin/env python3
"""
Random Video Clips Streaming Server
Main Flask application
Pushes pre-generated chunks to RTMP server for continuous live streaming
"""

import os
import signal
import sys
from flask import Flask, jsonify, request, Response, render_template, send_file
from flask_cors import CORS
from dotenv import load_dotenv

from clip_pusher import ClipPusher

# Load environment variables
load_dotenv()

app = Flask(__name__)
CORS(app)

# Configuration
CHUNK_FOLDER = os.getenv('CHUNK_FOLDER', '/chunks')
PORT = int(os.getenv('PORT', '8080'))
EXTERNAL_PORT = int(os.getenv('EXTERNAL_PORT', str(PORT)))
HLS_PORT = int(os.getenv('HLS_PORT', '8080'))
RTMP_URL = os.getenv('RTMP_URL', 'rtmp://nginx-rtmp:1935/live/stream')
AUDIO_FOLDER = os.getenv('AUDIO_FOLDER', '')

# Initialize components
print(f"Initializing Random Video Clips Streaming Server...")
print(f"Chunk folder: {CHUNK_FOLDER}")
print(f"RTMP URL: {RTMP_URL}")
print(f"Audio folder: {AUDIO_FOLDER or '(none — video audio used)'}")
print("Streaming mode: RTMP push (chunked stream)")

# Initialize clip pusher
clip_pusher = ClipPusher(CHUNK_FOLDER, RTMP_URL,
                         audio_folder=AUDIO_FOLDER if AUDIO_FOLDER else None)

@app.route('/')
def index():
    """Root endpoint - renders the UI dashboard"""
    current_status = clip_pusher.get_status()
    current_chunk = current_status.get('current_chunk')
    
    # Read chunks
    import os
    from datetime import datetime
    
    chunks = []
    if os.path.exists(CHUNK_FOLDER):
        for f in os.listdir(CHUNK_FOLDER):
            if f.endswith('.mp4') and not f.startswith('chunk_temp'):
                filepath = os.path.join(CHUNK_FOLDER, f)
                stat = os.stat(filepath)
                chunks.append({
                    'name': f,
                    'created_at': datetime.fromtimestamp(stat.st_ctime).strftime('%Y-%m-%d %H:%M:%S'),
                    'timestamp': stat.st_ctime,
                    'size_mb': round(stat.st_size / (1024 * 1024), 2)
                })
    
    # Sort chunks by oldest first (since they get pruned first)
    chunks.sort(key=lambda x: x['timestamp'])

    # List audio files (same extensions as clip_pusher)
    audio_files = []
    audio_extensions = ('.mp3', '.aac', '.flac', '.ogg', '.wav', '.m4a')
    if AUDIO_FOLDER and os.path.isdir(AUDIO_FOLDER):
        for root, _dirs, files in os.walk(AUDIO_FOLDER):
            for f in files:
                lower = f.lower()
                if any(lower.endswith(ext) for ext in audio_extensions):
                    path = os.path.join(root, f)
                    try:
                        stat = os.stat(path)
                        audio_files.append({
                            'name': os.path.basename(path),
                            'size_mb': round(stat.st_size / (1024 * 1024), 2)
                        })
                    except OSError:
                        pass
        audio_files.sort(key=lambda x: x['name'].lower())

    current_audio = current_status.get('current_audio')

    # Parse .env settings explicitly for the UI to display/edit
    settings = {}
    env_path = os.path.join(os.path.dirname(__file__), '.env')
    if os.path.exists(env_path):
        with open(env_path, 'r') as file:
            for line in file:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, val = line.split('=', 1)
                    settings[key] = val

    # Calculate expiration estimate for all chunks
    if chunks:
        import math
        max_chunks = int(settings.get('MAX_CHUNKS', '56'))
        chunks_per_run = int(settings.get('CHUNKS_PER_RUN', '4'))
        
        for i, chunk in enumerate(chunks):
            # chunk i will be deleted when i + (max_chunks - current_count) chunks are added
            remaining_till_expiry = max(0, max_chunks - len(chunks) + 1 + i)
            chunk['days_to_expire'] = math.ceil(remaining_till_expiry / chunks_per_run)

    # Gather System Information
    import platform
    import multiprocessing

    os_info = platform.system() + " " + platform.release()
    if os.path.exists('/etc/os-release'):
        with open('/etc/os-release', 'r') as f:
            for line in f:
                if line.startswith('PRETTY_NAME='):
                    os_info = line.split('=', 1)[1].strip().strip('"')
                    break

    is_docker = os.path.exists('/.dockerenv')

    try:
        cpu_count = multiprocessing.cpu_count()
    except NotImplementedError:
        cpu_count = 1

    # Memory (Linux /proc/meminfo; in Docker this is container view)
    mem_total_mb = None
    mem_available_mb = None
    if os.path.exists('/proc/meminfo'):
        try:
            with open('/proc/meminfo', 'r') as f:
                for line in f:
                    if line.startswith('MemTotal:'):
                        mem_total_mb = int(line.split()[1]) / 1024  # kB -> MB
                    elif line.startswith('MemAvailable:'):
                        mem_available_mb = int(line.split()[1]) / 1024
                    if mem_total_mb is not None and mem_available_mb is not None:
                        break
        except (ValueError, OSError):
            pass

    # Chunks disk usage (sum of current chunk sizes)
    chunks_total_mb = round(sum(c['size_mb'] for c in chunks), 2) if chunks else 0
    chunks_count = len(chunks)

    sys_info = {
        'os': os_info,
        'docker': 'Yes' if is_docker else 'No',
        'cpu_cores': cpu_count,
        'hw_accel': settings.get('HW_ACCEL', 'none'),
        'mem_total_mb': mem_total_mb,
        'mem_available_mb': mem_available_mb,
        'chunks_total_mb': chunks_total_mb,
        'chunks_count': chunks_count,
    }

    initial_stream_status = {
        'current_chunk': current_status.get('current_chunk'),
        'current_chunk_started_at': current_status.get('current_chunk_started_at'),
        'current_chunk_duration': current_status.get('current_chunk_duration'),
        'current_audio': current_status.get('current_audio'),
        'audio_position_sec': current_status.get('audio_position_sec'),
        'audio_track_duration_sec': current_status.get('audio_track_duration_sec'),
    }
    return render_template('dashboard.html', chunks=chunks, audio_files=audio_files, settings=settings, hls_port=HLS_PORT, sys_info=sys_info, current_chunk=current_chunk, current_audio=current_audio, initial_stream_status=initial_stream_status)


@app.route('/iptv.m3u')
def iptv_playlist():
    """IPTV playlist for TV apps - points to nginx-rtmp HLS stream"""
    base_url = request.host.split(':')[0]
    hls_url = f"http://{base_url}:{HLS_PORT}/hls/stream.m3u8"

    playlist_content = f"""#EXTM3U
#EXTINF:-1,Random Video Clips
{hls_url}
"""

    return Response(
        playlist_content,
        mimetype='application/vnd.apple.mpegurl',
        headers={
            'Content-Disposition': 'attachment; filename="random_clips.m3u"',
            'Access-Control-Allow-Origin': '*'
        }
    )

@app.route('/api/status')
def status():
    """Get server status"""
    pusher_status = clip_pusher.get_status()

    generation_in_progress = os.path.exists(os.path.join(CHUNK_FOLDER, '.generation_running'))

    status_data = {
        'server': 'running',
        'mode': 'RTMP push (chunked stream)',
        'stream_url': f'http://{request.host.split(":")[0]}:{HLS_PORT}/hls/stream.m3u8',
        'rtmp_pusher': pusher_status,
        'generation_in_progress': generation_in_progress,
        'config': {
            'chunk_folder': CHUNK_FOLDER,
            'port': EXTERNAL_PORT,
            'rtmp_url': RTMP_URL
        }
    }

    return jsonify(status_data)

@app.route('/api/stream-status')
def stream_status():
    """Get RTMP stream pusher status"""
    return jsonify(clip_pusher.get_status())

@app.route('/api/skip_to_next', methods=['POST'])
def skip_to_next():
    """Skip current chunk and advance to the next one."""
    skipped = clip_pusher.skip_to_next()
    return jsonify({'success': True, 'skipped': skipped})

@app.route('/chunks/<path:filename>')
def serve_chunk(filename):
    """Serve a chunk file for playback in the browser (read-only, safe path)."""
    if not filename or '..' in filename or '/' in filename or not filename.endswith('.mp4'):
        return jsonify({'error': 'Invalid filename'}), 400
    path = os.path.join(CHUNK_FOLDER, filename)
    if not os.path.abspath(path).startswith(os.path.abspath(CHUNK_FOLDER)):
        return jsonify({'error': 'Invalid path'}), 400
    if not os.path.isfile(path):
        return jsonify({'error': 'Not found'}), 404
    return send_file(path, mimetype='video/mp4', as_attachment=False)

@app.route('/api/generate_chunk', methods=['POST'])
def trigger_generation():
    """Trigger the chunk generator container to create new chunks manually"""
    running_file = os.path.join(CHUNK_FOLDER, '.generation_running')
    if os.path.exists(running_file):
        return jsonify({
            'success': False,
            'error': 'Chunk generation is already running. Please wait for it to finish.'
        }), 409
    trigger_file = os.path.join(CHUNK_FOLDER, '.trigger_generation')
    try:
        with open(trigger_file, 'w') as f:
            f.write('manual\n')
        return jsonify({'success': True, 'message': 'Triggered chunk generation. The chunk-generator container will start processing momentarily.'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

def start_clip_pusher():
    """Start the RTMP clip pusher"""
    clip_pusher.start()

def shutdown_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    print("Shutting down clip pusher...")
    clip_pusher.stop()
    sys.exit(0)

# Register shutdown handlers
signal.signal(signal.SIGTERM, shutdown_handler)
signal.signal(signal.SIGINT, shutdown_handler)

# Clip pusher is started in the worker via gunicorn post_fork (see gunicorn.conf.py),
# so API status and the push loop run in the same process. When running as __main__,
# we start it here before app.run().
if __name__ == '__main__':
    start_clip_pusher()
    try:
        print(f"\nStarting server internally on port {PORT}...")
        print(f"External API port exposed mapping: {EXTERNAL_PORT}")
        print(f"RTMP stream: {RTMP_URL}")
        print(f"HLS playback: http://localhost:{HLS_PORT}/hls/stream.m3u8")
        print(f"API: http://localhost:{EXTERNAL_PORT}/api/status")

        app.run(host='0.0.0.0', port=PORT, debug=False, threaded=True)
    except Exception as e:
        print(f"Error starting Flask server: {e}")
        clip_pusher.stop()
        import traceback
        traceback.print_exc()
        raise

