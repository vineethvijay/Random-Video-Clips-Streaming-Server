#!/usr/bin/env python3
"""
Random Video Clips Streaming Server
Main Flask application
Pushes pre-generated chunks to RTMP server for continuous live streaming
"""

import html
import json
import os
import time
import re
import signal
import sys
import urllib.request
from flask import Flask, jsonify, request, Response, render_template, send_file
from flask_cors import CORS
from werkzeug.middleware.proxy_fix import ProxyFix
from dotenv import load_dotenv

from clip_pusher import ClipPusher

# Load environment variables
load_dotenv()

app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)
CORS(app)

# Configuration
CHUNK_FOLDER = os.getenv('CHUNK_FOLDER', '/chunks')
TRIGGER_DIR = os.getenv('TRIGGER_DIR', '').strip() or None
PORT = int(os.getenv('PORT', '8080'))
EXTERNAL_PORT = int(os.getenv('EXTERNAL_PORT', str(PORT)))
HLS_PORT = int(os.getenv('HLS_PORT', '8080'))
RTMP_URL = os.getenv('RTMP_URL', 'rtmp://nginx-rtmp:1935/live/stream')
AUDIO_FOLDER = os.getenv('AUDIO_FOLDER', '')
# Persistent stats dir (mount this volume so hours played / chunks created survive new deployments)
STATS_DIR = os.getenv('STATS_DIR', '').strip() or None
# Host crontab path (inside container) for programmatic cron. Mount host /var/spool/cron/crontabs to /host-crontab.
HOST_CRONTAB_PATH = os.getenv('HOST_CRONTAB_PATH', '').strip() or None
# Project root on host (for cron command). e.g. /root/new-random-vid-player
PROJECT_ROOT = os.getenv('PROJECT_ROOT', '').strip() or None

CRON_JOB_COMMENT = 'random-video-streamer chunk-gen'

# Initialize components
print(f"Initializing Random Video Clips Streaming Server...")
print(f"Chunk folder: {CHUNK_FOLDER}")
print(f"RTMP URL: {RTMP_URL}")
print(f"Audio folder: {AUDIO_FOLDER or '(none — video audio used)'}")
print(f"Stats dir (persistent): {STATS_DIR or CHUNK_FOLDER}")
print("Streaming mode: RTMP push (chunked stream)")

# Initialize clip pusher
clip_pusher = ClipPusher(CHUNK_FOLDER, RTMP_URL,
                         audio_folder=AUDIO_FOLDER if AUDIO_FOLDER else None,
                         stats_dir=STATS_DIR)

INITIAL_CHUNKS_LIMIT = 20


def _format_time_played(seconds):
    """Format seconds as y,m,d,h (e.g. '1y 2m 3d 4h')."""
    if seconds is None or seconds < 0:
        return None
    sec = int(seconds)
    if sec == 0:
        return '0h'
    y, r = divmod(sec, 365 * 24 * 3600)
    m, r = divmod(r, 30 * 24 * 3600)
    d, r = divmod(r, 24 * 3600)
    h = r // 3600
    parts = []
    if y: parts.append(f'{y}y')
    if m: parts.append(f'{m}m')
    if d: parts.append(f'{d}d')
    if h or not parts: parts.append(f'{h}h')
    return ' '.join(parts)


def _build_chunks_list(settings=None):
    """Build chunks list (no ffprobe). settings used for days_to_expire."""
    from datetime import datetime
    import json as _json
    import math
    settings = settings or {}
    chunks = []
    if os.path.exists(CHUNK_FOLDER):
        for f in os.listdir(CHUNK_FOLDER):
            if f.endswith('.mp4') and not f.startswith('chunk_temp'):
                filepath = os.path.join(CHUNK_FOLDER, f)
                stat = os.stat(filepath)
                meta_path = os.path.join(CHUNK_FOLDER, f.replace('.mp4', '.meta.json'))
                source_videos = []
                model_info = []
                video_codec = None
                width = None
                height = None
                created_at_str = None
                if os.path.isfile(meta_path):
                    try:
                        with open(meta_path, 'r') as _f:
                            meta = _json.load(_f)
                            raw_sources = meta.get('source_videos') or []
                            # Normalize: support old [path, ...] and new [{path, model}, ...]
                            source_videos = []
                            for item in raw_sources:
                                if isinstance(item, str):
                                    source_videos.append({'path': item, 'model': None, 'thumbnail_url': None, 'title': None, 'channel': None})
                                elif isinstance(item, dict) and 'path' in item:
                                    source_videos.append({
                                        'path': item['path'],
                                        'model': item.get('model'),
                                        'thumbnail_url': item.get('thumbnail_url'),
                                        'title': item.get('title'),
                                        'channel': item.get('channel'),
                                    })
                            model_info = meta.get('model_info') or []
                            video_codec = meta.get('video_codec')
                            width = meta.get('width')
                            height = meta.get('height')
                            created_at_str = meta.get('created_at')
                    except (ValueError, OSError):
                        pass
                if created_at_str:
                    try:
                        dt = datetime.fromisoformat(created_at_str.replace('Z', '+00:00'))
                        created_at_display = dt.strftime('%Y-%m-%d %H:%M:%S')
                        timestamp = dt.timestamp()
                    except (ValueError, TypeError):
                        created_at_display = datetime.fromtimestamp(stat.st_ctime).strftime('%Y-%m-%d %H:%M:%S')
                        timestamp = stat.st_ctime
                else:
                    created_at_display = datetime.fromtimestamp(stat.st_ctime).strftime('%Y-%m-%d %H:%M:%S')
                    timestamp = stat.st_ctime
                chunks.append({
                    'name': f,
                    'created_at': created_at_display,
                    'timestamp': timestamp,
                    'size_mb': round(stat.st_size / (1024 * 1024), 2),
                    'source_videos': source_videos,
                    'model_info': model_info,
                    'video_codec': video_codec,
                    'width': width,
                    'height': height,
                })
    chunks.sort(key=lambda x: x['timestamp'], reverse=True)
    if chunks:
        max_chunks = int(settings.get('MAX_CHUNKS', '56'))
        chunks_per_run = int(settings.get('CHUNKS_PER_RUN', '4'))
        for i, chunk in enumerate(chunks):
            remaining_till_expiry = max(0, max_chunks - i)
            chunk['days_to_expire'] = math.ceil(remaining_till_expiry / chunks_per_run)
    return chunks


@app.route('/')
def index():
    """Root endpoint - renders the UI dashboard"""
    current_status = clip_pusher.get_status()
    current_chunk = current_status.get('current_chunk')

    # Parse .env for settings (needed for chunks)
    settings = {}
    env_path = os.path.join(os.path.dirname(__file__), '.env')
    if os.path.exists(env_path):
        with open(env_path, 'r') as file:
            for line in file:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, val = line.split('=', 1)
                    settings[key] = val

    chunks = _build_chunks_list(settings)

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
                        rel_path = os.path.relpath(path, AUDIO_FOLDER)
                        audio_files.append({
                            'name': os.path.basename(path),
                            'path': path,
                            'rel_path': rel_path,
                            'size_mb': round(stat.st_size / (1024 * 1024), 2)
                        })
                    except OSError:
                        pass
        audio_files.sort(key=lambda x: x['name'].lower())

    current_audio = current_status.get('current_audio')

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

    # Chunk folder mount total/available (filesystem size)
    chunk_mount_total_mb = None
    chunk_mount_available_mb = None
    if os.path.exists(CHUNK_FOLDER):
        try:
            st = os.statvfs(CHUNK_FOLDER)
            chunk_mount_total_mb = round((st.f_frsize * st.f_blocks) / (1024 * 1024), 1)
            chunk_mount_available_mb = round((st.f_frsize * st.f_bavail) / (1024 * 1024), 1)
        except OSError:
            pass

    nvidia_available = settings.get('HW_ACCEL') == 'nvidia'  # trust .env if already set
    if not nvidia_available:
        try:
            import subprocess
            r = subprocess.run(['nvidia-smi', '--query-gpu=name', '--format=csv,noheader'], capture_output=True, text=True, timeout=5)
            nvidia_available = r.returncode == 0 and bool(r.stdout.strip())
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError, ValueError):
            pass

    sys_info = {
        'os': os_info,
        'docker': 'Yes' if is_docker else 'No',
        'cpu_cores': cpu_count,
        'hw_accel': settings.get('HW_ACCEL', 'none'),
        'nvidia_available': nvidia_available,
        'mem_total_mb': mem_total_mb,
        'mem_available_mb': mem_available_mb,
        'chunks_total_mb': chunks_total_mb,
        'chunks_count': chunks_count,
        'chunk_mount_total_mb': chunk_mount_total_mb,
        'chunk_mount_available_mb': chunk_mount_available_mb,
    }

    initial_stream_status = {
        'current_chunk': current_status.get('current_chunk'),
        'current_chunk_started_at': current_status.get('current_chunk_started_at'),
        'current_chunk_duration': current_status.get('current_chunk_duration'),
        'current_audio': current_status.get('current_audio'),
        'audio_position_sec': current_status.get('audio_position_sec'),
        'audio_track_duration_sec': current_status.get('audio_track_duration_sec'),
    }
    stream_stats = {
        'time_played': _format_time_played(current_status.get('total_seconds_streamed')),
        'chunks_pushed': current_status.get('chunks_pushed'),
        'chunks_created_total': current_status.get('chunks_created_total'),
        'total_seconds_streamed': current_status.get('total_seconds_streamed'),
    }
    current_chunk_data = next((c for c in chunks if c['name'] == current_chunk), None) if current_chunk else None
    chunks_excluding_current = [c for c in chunks if c['name'] != current_chunk]
    show_model_column = bool((settings.get('TUBEARCHIVIST_URL') or '').strip() and (settings.get('TUBEARCHIVIST_TOKEN') or '').strip())
    tubearchivist_url = (settings.get('TUBEARCHIVIST_URL') or '').strip().rstrip('/')
    hls_url = _stream_url()
    return render_template('dashboard.html', chunks=chunks, chunks_excluding_current=chunks_excluding_current, current_chunk_data=current_chunk_data, audio_files=audio_files, settings=settings, show_model_column=show_model_column, tubearchivist_url=tubearchivist_url, hls_port=HLS_PORT, hls_url=hls_url, sys_info=sys_info, current_chunk=current_chunk, current_audio=current_audio, initial_stream_status=initial_stream_status, stream_stats=stream_stats, initial_chunks_limit=INITIAL_CHUNKS_LIMIT)


def _admin_context():
    """Build settings, sys_info, stream_stats for admin page."""
    current_status = clip_pusher.get_status()
    settings = {}
    env_path = os.path.join(os.path.dirname(__file__), '.env')
    if os.path.exists(env_path):
        with open(env_path, 'r') as file:
            for line in file:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, val = line.split('=', 1)
                    settings[key] = val

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
    mem_total_mb = mem_available_mb = None
    if os.path.exists('/proc/meminfo'):
        try:
            with open('/proc/meminfo', 'r') as f:
                for line in f:
                    if line.startswith('MemTotal:'):
                        mem_total_mb = int(line.split()[1]) / 1024
                    elif line.startswith('MemAvailable:'):
                        mem_available_mb = int(line.split()[1]) / 1024
                    if mem_total_mb is not None and mem_available_mb is not None:
                        break
        except (ValueError, OSError):
            pass
    chunks_total_mb = 0
    chunks_count = 0
    if os.path.exists(CHUNK_FOLDER):
        for f in os.listdir(CHUNK_FOLDER):
            if f.endswith('.mp4') and not f.startswith('chunk_temp'):
                chunks_count += 1
                try:
                    chunks_total_mb += os.path.getsize(os.path.join(CHUNK_FOLDER, f)) / (1024 * 1024)
                except OSError:
                    pass
    chunks_total_mb = round(chunks_total_mb, 2)
    chunk_mount_total_mb = chunk_mount_available_mb = None
    if os.path.exists(CHUNK_FOLDER):
        try:
            st = os.statvfs(CHUNK_FOLDER)
            chunk_mount_total_mb = round((st.f_frsize * st.f_blocks) / (1024 * 1024), 1)
            chunk_mount_available_mb = round((st.f_frsize * st.f_bavail) / (1024 * 1024), 1)
        except OSError:
            pass
    nvidia_available = settings.get('HW_ACCEL') == 'nvidia'
    if not nvidia_available:
        try:
            import subprocess
            r = subprocess.run(['nvidia-smi', '--query-gpu=name', '--format=csv,noheader'], capture_output=True, text=True, timeout=5)
            nvidia_available = r.returncode == 0 and bool(r.stdout.strip())
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError, ValueError):
            pass
    sys_info = {
        'os': os_info, 'docker': 'Yes' if is_docker else 'No', 'cpu_cores': cpu_count,
        'hw_accel': settings.get('HW_ACCEL', 'none'), 'nvidia_available': nvidia_available,
        'mem_total_mb': mem_total_mb, 'mem_available_mb': mem_available_mb,
        'chunks_total_mb': chunks_total_mb, 'chunks_count': chunks_count,
        'chunk_mount_total_mb': chunk_mount_total_mb, 'chunk_mount_available_mb': chunk_mount_available_mb,
    }
    host_cron_schedule = (settings.get('CRON_SCHEDULE') or '0 2 * * *').strip()
    host_cron_port = EXTERNAL_PORT
    host_cron_log = 'stats/cron.log'
    cron_available = _cron_available()
    cron_schedule, cron_command = _cron_get_job() if cron_available else (None, None)
    return {
        'settings': settings, 'sys_info': sys_info,
        'host_cron_schedule': host_cron_schedule, 'host_cron_port': host_cron_port, 'host_cron_log': host_cron_log,
        'cron_available': cron_available, 'cron_schedule': cron_schedule, 'cron_command': cron_command,
    }


@app.route('/admin')
def admin():
    """Admin page: Server Configuration, Cron history, System Information"""
    ctx = _admin_context()
    return render_template('admin.html', **ctx)


def _fetch_og_meta(url: str, timeout: float = 5.0) -> dict:
    """Fetch og:title and og:image from URL. Returns {title, image} or empty dict on failure."""
    if not url or not url.startswith(('http://', 'https://')):
        return {}
    cache_dir = STATS_DIR or CHUNK_FOLDER
    cache_path = os.path.join(cache_dir, '.model_meta_cache.json')
    cache = {}
    if os.path.isfile(cache_path):
        try:
            with open(cache_path, 'r') as f:
                cache = json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    cached = cache.get(url)
    if cached and isinstance(cached, dict):
        ts = cached.get('_ts', 0)
        if ts and (time.time() - ts) < 86400:  # 24h TTL
            return {k: v for k, v in cached.items() if k != '_ts'}
    result = {}
    try:
        req = urllib.request.Request(
            url,
            headers={
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml',
                'Accept-Language': 'en-US,en;q=0.9',
            },
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            html_content = resp.read().decode('utf-8', errors='replace')
        m_title = re.search(r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)["\']', html_content, re.I)
        if not m_title:
            m_title = re.search(r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:title["\']', html_content, re.I)
        m_image = re.search(r'<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)["\']', html_content, re.I)
        if not m_image:
            m_image = re.search(r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:image["\']', html_content, re.I)
        if m_title:
            result['title'] = html.unescape(m_title.group(1).strip())[:120]
        if m_image:
            result['image'] = m_image.group(1).strip()
    except Exception:
        pass
    cache[url] = dict(result, _ts=time.time())
    try:
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        with open(cache_path, 'w') as f:
            json.dump(cache, f, indent=2)
    except OSError:
        pass
    return result


def _stats_context():
    """Build stream_stats and play_counts for stats page."""
    current_status = clip_pusher.get_status()
    stream_stats = {
        'time_played': _format_time_played(current_status.get('total_seconds_streamed')),
        'chunks_pushed': current_status.get('chunks_pushed'),
        'chunks_created_total': current_status.get('chunks_created_total'),
        'total_seconds_streamed': current_status.get('total_seconds_streamed'),
    }
    play_counts = clip_pusher.get_play_counts()
    # Enrich models with og:title, og:image, and YouTube thumbnail (when video_id available)
    models_enriched = []
    for item in play_counts.get('models', []):
        model, count = item[0], item[1]
        video_id = item[2] if len(item) > 2 else None
        stored_thumb = item[3] if len(item) > 3 else None
        url = model if model.startswith('http') else 'https://' + model
        meta = _fetch_og_meta(url)
        title = html.unescape(meta.get('title') or url)
        # Prefer YouTube thumbnail from video_id (play_counts) when available; else stored_thumb, else OG image
        thumbnail = (f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg" if video_id else None) or stored_thumb or meta.get('image')
        models_enriched.append({
            'url': url,
            'count': count,
            'title': title,
            'image': thumbnail,
        })
    play_counts = dict(play_counts, models=models_enriched)
    return {'stream_stats': stream_stats, 'play_counts': play_counts}


@app.route('/stats')
def stats():
    """Stats page: Stream stats, top models, top audio by play count"""
    ctx = _stats_context()
    return render_template('stats.html', **ctx)


def _stream_url():
    """Build HLS stream URL (respects X-Forwarded-Proto when behind HTTPS proxy)."""
    if request.scheme == 'https':
        return f"https://{request.host}/hls/stream.m3u8"
    return f"http://{request.host.split(':')[0]}:{HLS_PORT}/hls/stream.m3u8"


@app.route('/iptv.m3u')
def iptv_playlist():
    """IPTV playlist for TV apps - points to nginx-rtmp HLS stream"""
    hls_url = _stream_url()

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
        'stream_url': _stream_url(),
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


@app.route('/api/chunks')
def api_chunks():
    """Get chunks with pagination (offset, limit). Used for loading more chunks on dashboard."""
    settings = {}
    env_path = os.path.join(os.path.dirname(__file__), '.env')
    if os.path.exists(env_path):
        with open(env_path, 'r') as file:
            for line in file:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, val = line.split('=', 1)
                    settings[key] = val
    chunks = _build_chunks_list(settings)
    exclude = request.args.get('exclude', '').strip()
    if exclude:
        chunks = [c for c in chunks if c['name'] != exclude]
    offset = max(0, int(request.args.get('offset', 0)))
    limit = min(100, max(1, int(request.args.get('limit', 20))))
    page_chunks = chunks[offset:offset + limit]
    return jsonify({'chunks': page_chunks, 'total': len(chunks)})


@app.route('/api/cron-run-history')
def cron_run_history():
    """Get chunk-generator cron/manual run history from stats/.cron_run_history (paginated)"""
    stats_dir = STATS_DIR or CHUNK_FOLDER
    history_path = os.path.join(stats_dir, '.cron_run_history')
    entries = []
    if os.path.isfile(history_path):
        try:
            with open(history_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    parts = line.split(None, 1)
                    if len(parts) >= 2:
                        entries.append({'timestamp': parts[0], 'trigger': parts[1]})
                    elif len(parts) == 1:
                        entries.append({'timestamp': parts[0], 'trigger': 'cron'})
            entries.reverse()
        except (OSError, ValueError):
            pass
    per_page = min(int(request.args.get('per_page', 20)), 100)
    page = max(1, int(request.args.get('page', 1)))
    total = len(entries)
    total_pages = max(1, (total + per_page - 1) // per_page)
    page = min(page, total_pages)
    start = (page - 1) * per_page
    return jsonify({
        'entries': entries[start:start + per_page],
        'page': page,
        'per_page': per_page,
        'total': total,
        'total_pages': total_pages,
    })


def _cron_available():
    """True if host crontab is mounted and we can manage it."""
    return bool(HOST_CRONTAB_PATH and os.path.exists(os.path.dirname(HOST_CRONTAB_PATH)))


def _get_cron_tab():
    """Open host crontab for root. Returns CronTab or None."""
    if not _cron_available():
        return None
    try:
        from crontab import CronTab
        return CronTab(tabfile=HOST_CRONTAB_PATH)
    except Exception:
        return None


def _cron_get_job():
    """Get our cron job if present. Returns (schedule_str, command) or (None, None)."""
    tab = _get_cron_tab()
    if not tab:
        return None, None
    for job in tab:
        if job.comment and CRON_JOB_COMMENT in job.comment:
            parts = str(job).split(None, 5)
            schedule = ' '.join(parts[:5]) if len(parts) >= 5 else None
            return schedule, job.command
    return None, None


def _cron_set(schedule: str) -> tuple[bool, str]:
    """Set or update our cron job. Returns (success, message)."""
    if not _cron_available():
        return False, 'Host crontab not mounted. Set HOST_CRONTAB_PATH and mount /var/spool/cron/crontabs.'
    if not PROJECT_ROOT:
        return False, 'PROJECT_ROOT not set. Required for cron command.'
    schedule = (schedule or '').strip()
    if not schedule:
        return False, 'Schedule cannot be empty.'
    try:
        from crontab import CronTab
        tab = CronTab(tabfile=HOST_CRONTAB_PATH)
        # Remove existing job
        for job in list(tab):
            if job.comment and CRON_JOB_COMMENT in job.comment:
                tab.remove(job)
        # Add new job
        log_path = os.path.join(PROJECT_ROOT, 'stats', 'cron.log')
        cmd = f'cd {PROJECT_ROOT} && curl -s -X POST "http://localhost:{EXTERNAL_PORT}/api/generate_chunk?source=cron" >> {log_path} 2>&1'
        job = tab.new(command=cmd, comment=CRON_JOB_COMMENT)
        job.setall(schedule)
        tab.write()
        return True, 'Cron job updated.'
    except Exception as e:
        return False, str(e)


def _cron_remove() -> tuple[bool, str]:
    """Remove our cron job. Returns (success, message)."""
    if not _cron_available():
        return False, 'Host crontab not mounted.'
    try:
        from crontab import CronTab
        tab = CronTab(tabfile=HOST_CRONTAB_PATH)
        removed = 0
        for job in list(tab):
            if job.comment and CRON_JOB_COMMENT in job.comment:
                tab.remove(job)
                removed += 1
        if removed:
            tab.write()
        return True, 'Cron job removed.' if removed else 'No cron job found.'
    except Exception as e:
        return False, str(e)


@app.route('/api/cron', methods=['GET', 'POST', 'DELETE'])
def api_cron():
    """GET: current cron job. POST: set schedule. DELETE: remove job."""
    if request.method == 'GET':
        available = _cron_available()
        schedule, command = _cron_get_job() if available else (None, None)
        return jsonify({
            'available': available,
            'schedule': schedule,
            'command': command,
            'project_root': PROJECT_ROOT,
        })
    if request.method == 'POST':
        data = request.get_json() or {}
        schedule = data.get('schedule', '').strip()
        ok, msg = _cron_set(schedule)
        if ok:
            return jsonify({'success': True, 'message': msg})
        return jsonify({'success': False, 'error': msg}), 400
    if request.method == 'DELETE':
        ok, msg = _cron_remove()
        if ok:
            return jsonify({'success': True, 'message': msg})
        return jsonify({'success': False, 'error': msg}), 400


def _read_proc_stat_cpu():
    """Read first line of /proc/stat (aggregate CPU). Returns (user, nice, system, idle, iowait, irq, softirq) or None."""
    try:
        with open('/proc/stat', 'r') as f:
            line = f.readline()
        if line.startswith('cpu '):
            parts = line.split()
            # cpu  user nice system idle iowait irq softirq steal guest guest_nice
            return tuple(int(x) for x in parts[1:8])
    except (OSError, ValueError):
        return None


@app.route('/api/system-usage')
def system_usage():
    """Live CPU, memory, and optional GPU usage for the dashboard."""
    import time
    import subprocess
    out = {
        'cpu_percent': None,
        'mem_used_mb': None,
        'mem_total_mb': None,
        'mem_percent': None,
        'gpu_percent': None,
        'gpu_mem_used_mb': None,
        'gpu_mem_total_mb': None,
    }
    # CPU: two samples of /proc/stat
    s1 = _read_proc_stat_cpu()
    if s1:
        time.sleep(0.3)
        s2 = _read_proc_stat_cpu()
        if s2:
            busy1 = s1[0] + s1[1] + s1[2] + s1[5] + s1[6]
            total1 = busy1 + s1[3] + s1[4]
            busy2 = s2[0] + s2[1] + s2[2] + s2[5] + s2[6]
            total2 = busy2 + s2[3] + s2[4]
            delta_total = total2 - total1
            if delta_total > 0:
                out['cpu_percent'] = round(100.0 * (busy2 - busy1) / delta_total, 1)
    # Memory
    if os.path.exists('/proc/meminfo'):
        try:
            with open('/proc/meminfo', 'r') as f:
                total_kb = avail_kb = None
                for line in f:
                    if line.startswith('MemTotal:'):
                        total_kb = int(line.split()[1])
                    elif line.startswith('MemAvailable:'):
                        avail_kb = int(line.split()[1])
                    if total_kb is not None and avail_kb is not None:
                        break
            if total_kb and total_kb > 0:
                used_kb = total_kb - avail_kb
                out['mem_total_mb'] = round(total_kb / 1024, 1)
                out['mem_used_mb'] = round(used_kb / 1024, 1)
                out['mem_percent'] = round(100.0 * used_kb / total_kb, 1)
        except (ValueError, OSError):
            pass
    # GPU (nvidia-smi)
    try:
        result = subprocess.run(
            [
                'nvidia-smi',
                '--query-gpu=utilization.gpu,memory.used,memory.total',
                '--format=csv,noheader,nounits',
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            parts = result.stdout.strip().splitlines()[0].split(',')
            if len(parts) >= 3:
                out['gpu_percent'] = int(parts[0].strip().split()[0] or 0)
                out['gpu_mem_used_mb'] = float(parts[1].strip().split()[0] or 0)
                out['gpu_mem_total_mb'] = float(parts[2].strip().split()[0] or 0)
    except (FileNotFoundError, subprocess.TimeoutExpired, ValueError):
        pass
    return jsonify(out)

@app.route('/api/skip_to_next', methods=['POST'])
def skip_to_next():
    """Skip current chunk and advance to the next one."""
    skipped = clip_pusher.skip_to_next()
    return jsonify({'success': True, 'skipped': skipped})


@app.route('/api/skip_to_next_audio', methods=['POST'])
def skip_to_next_audio():
    """Skip to the next audio track."""
    skipped = clip_pusher.skip_to_next_audio()
    return jsonify({'success': True, 'skipped': skipped})


@app.route('/api/play_chunk', methods=['POST'])
def play_chunk():
    """Play a specific chunk next in the live stream."""
    data = request.get_json()
    chunk_name = data.get('chunk_name') if data else None
    if not chunk_name or not isinstance(chunk_name, str):
        return jsonify({'success': False, 'error': 'Missing or invalid chunk_name'}), 400
    ok = clip_pusher.play_chunk(chunk_name)
    if not ok:
        return jsonify({'success': False, 'error': 'Chunk not found'}), 404
    return jsonify({'success': True})


@app.route('/api/delete_audio', methods=['POST'])
def delete_audio():
    """Delete an audio file from the filesystem. Requires path within AUDIO_FOLDER.
    If the file is currently playing, skips to next track first."""
    if not AUDIO_FOLDER:
        return jsonify({'success': False, 'error': 'AUDIO_FOLDER not configured'}), 400
    data = request.get_json()
    path = data.get('path') if data else None
    if not path or not isinstance(path, str):
        return jsonify({'success': False, 'error': 'Missing or invalid path'}), 400
    abs_path = os.path.abspath(path)
    abs_audio = os.path.abspath(AUDIO_FOLDER)
    if not abs_path.startswith(abs_audio):
        return jsonify({'success': False, 'error': 'Path must be within AUDIO_FOLDER'}), 400
    if not os.path.isfile(abs_path):
        return jsonify({'success': False, 'error': 'File not found'}), 404
    # If this is the current playing audio, skip to next first
    current_path = clip_pusher._persistent_audio_path
    if current_path and os.path.abspath(current_path) == abs_path:
        clip_pusher.skip_to_next_audio()
    try:
        os.remove(abs_path)
        return jsonify({'success': True})
    except OSError as e:
        return jsonify({'success': False, 'error': str(e)}), 500


AUDIO_MIMETYPES = {
    '.mp3': 'audio/mpeg',
    '.aac': 'audio/aac',
    '.flac': 'audio/flac',
    '.ogg': 'audio/ogg',
    '.wav': 'audio/wav',
    '.m4a': 'audio/mp4',
}


@app.route('/audio/<path:relpath>')
def serve_audio(relpath):
    """Serve an audio file for playback in the browser (read-only, path within AUDIO_FOLDER)."""
    if not AUDIO_FOLDER:
        return jsonify({'error': 'AUDIO_FOLDER not configured'}), 400
    if not relpath or '..' in relpath:
        return jsonify({'error': 'Invalid path'}), 400
    path = os.path.normpath(os.path.join(AUDIO_FOLDER, relpath))
    if not os.path.abspath(path).startswith(os.path.abspath(AUDIO_FOLDER)):
        return jsonify({'error': 'Invalid path'}), 400
    if not os.path.isfile(path):
        return jsonify({'error': 'Not found'}), 404
    ext = os.path.splitext(path)[1].lower()
    mimetype = AUDIO_MIMETYPES.get(ext, 'audio/mpeg')
    return send_file(path, mimetype=mimetype, as_attachment=False)


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
    # Prefer /app/trigger (named volume) when mounted – avoids host permission issues on Proxmox
    trigger_dir = TRIGGER_DIR or ('/app/trigger' if os.path.isdir('/app/trigger') else None) or STATS_DIR or CHUNK_FOLDER
    trigger_file = os.path.join(trigger_dir, '.trigger_generation')
    trigger_type = 'cron' if request.args.get('source') == 'cron' else 'manual'
    try:
        os.makedirs(trigger_dir, exist_ok=True)
        with open(trigger_file, 'w') as f:
            f.write(trigger_type + '\n')
        return jsonify({'success': True, 'message': 'Triggered chunk generation. The chunk-generator container will start processing momentarily.'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


EDITABLE_SETTINGS = {'MAX_CHUNKS', 'CHUNK_DURATION', 'CLIP_MIN', 'CLIP_MAX', 'CHUNKS_PER_RUN', 'HW_ACCEL'}

@app.route('/api/update_settings', methods=['POST'])
def update_settings():
    """Update editable .env settings (all config fields)"""
    data = request.get_json()
    if not data or not isinstance(data, dict):
        return jsonify({'success': False, 'error': 'Invalid JSON body'}), 400
    env_path = os.path.join(os.path.dirname(__file__), '.env')
    if not os.path.exists(env_path):
        return jsonify({'success': False, 'error': '.env file not found'}), 500
    updates = {}
    for k, v in data.items():
        if k not in EDITABLE_SETTINGS:
            continue
        s = str(v).strip().strip('"').strip("'")
        updates[k] = s
    if not updates:
        return jsonify({'success': False, 'error': 'No valid settings to update'}), 400

    def env_value(s):
        return f'"{s}"' if ' ' in s else s

    try:
        lines = []
        updated_keys = set()
        with open(env_path, 'r') as f:
            for line in f:
                stripped = line.strip()
                if stripped and not stripped.startswith('#') and '=' in stripped:
                    key = stripped.split('=', 1)[0]
                    if key in updates:
                        lines.append(f"{key}={env_value(updates[key])}\n")
                        updated_keys.add(key)
                        continue
                lines.append(line)
        for k, v in updates.items():
            if k not in updated_keys:
                lines.append(f"{k}={env_value(v)}\n")
        with open(env_path, 'w') as f:
            f.writelines(lines)
        return jsonify({'success': True, 'updated': list(updates.keys()), 'message': 'Restart chunk-generator for changes: docker compose restart chunk-generator'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/restart_chunk_generator', methods=['POST'])
def restart_chunk_generator():
    """Restart the chunk-generator container via Docker API"""
    try:
        import docker
        # Use Unix socket directly to avoid "http+docker" scheme errors (requests 2.32+ / Docker Desktop)
        client = docker.DockerClient(base_url='unix:///var/run/docker.sock')
        container = client.containers.get('chunk-generator')
        container.restart()
        return jsonify({'success': True, 'message': 'chunk-generator restarted'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/stop_generation', methods=['POST'])
def stop_generation():
    """Force stop chunk generation by creating a stop signal and clearing running flag"""
    running_file = os.path.join(CHUNK_FOLDER, '.generation_running')
    stop_file = os.path.join(CHUNK_FOLDER, '.stop_generation')
    if not os.path.exists(running_file):
        return jsonify({
            'success': False,
            'error': 'No chunk generation is currently running.'
        }), 409
    try:
        with open(stop_file, 'w') as f:
            f.write('1')
        try:
            os.remove(running_file)
        except OSError:
            pass
        return jsonify({'success': True, 'message': 'Stop signal sent. Generation will halt after the current chunk.'})
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

