#!/usr/bin/env python3
"""
Random Video Clips Streaming Server
Main Flask application
Pushes pre-generated chunks to RTMP server for continuous live streaming
"""

import os
import signal
import sys
from flask import Flask, jsonify, request, Response
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
    """Root endpoint"""
    return jsonify({
        'service': 'Random Video Clips Streaming Server',
        'version': '3.0.0',
        'mode': 'RTMP push (chunked stream)',
        'stream_url': f'http://{request.host.split(":")[0]}:8080/hls/stream.m3u8',
        'endpoints': {
            'iptv': '/iptv.m3u',
            'status': '/api/status',
            'stream_status': '/api/stream-status',
        }
    })

@app.route('/iptv.m3u')
def iptv_playlist():
    """IPTV playlist for TV apps - points to nginx-rtmp HLS stream"""
    base_url = request.host.split(':')[0]
    hls_url = f"http://{base_url}:8080/hls/stream.m3u8"

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

    status_data = {
        'server': 'running',
        'mode': 'RTMP push (chunked stream)',
        'stream_url': f'http://{request.host.split(":")[0]}:8080/hls/stream.m3u8',
        'rtmp_pusher': pusher_status,
        'config': {
            'chunk_folder': CHUNK_FOLDER,
            'port': PORT,
            'rtmp_url': RTMP_URL
        }
    }

    return jsonify(status_data)

@app.route('/api/stream-status')
def stream_status():
    """Get RTMP stream pusher status"""
    return jsonify(clip_pusher.get_status())

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

# Start clip pusher when the module loads
start_clip_pusher()

if __name__ == '__main__':
    try:
        print(f"\nStarting server on port {PORT}...")
        print(f"RTMP stream: {RTMP_URL}")
        print(f"HLS playback: http://localhost:8080/hls/stream.m3u8")
        print(f"API: http://localhost:{PORT}/api/status")

        app.run(host='0.0.0.0', port=PORT, debug=False, threaded=True)
    except Exception as e:
        print(f"Error starting Flask server: {e}")
        clip_pusher.stop()
        import traceback
        traceback.print_exc()
        raise

