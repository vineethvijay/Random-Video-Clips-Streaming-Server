# Random Video Clips Streaming Server

A containerized live streaming server that continuously shuffles random clips from your video collection and plays them as a never-ending HLS live stream — with optional continuous background audio that plays independently from the video shuffling.

## Features

- **Continuous live stream** — no playback gaps; clips are piped into a single persistent RTMP connection
- **Continuous background audio** — mount an MP3 folder; audio plays uninterrupted while video clips shuffle
- **Smart shuffle** — avoids repeats until all segments of all videos have been played, then resets
- **Normalized output** — all clips transcoded to a consistent resolution/fps so transitions are smooth
- **Compatible** — works with VLC, Safari, Samsung TV IPTV apps, and any HLS player
- **Production-grade** — Gunicorn + gevent, tini init for zombie reaping, healthchecks, log rotation

## Architecture

```
Video clips  →  FFmpeg (extract, normalize, no audio)  →  pipe
MP3 folder   →  FFmpeg (loop forever)  ─────────────────────┐
                                                             ├─► nginx-rtmp ─► HLS
Clip Pusher  →  persistent RTMP connection  ────────────────┘
```

Two containers:
- **nginx-rtmp** — receives the RTMP feed, writes HLS segments to tmpfs
- **random-video-streamer** — picks random clips, extracts them silently, pipes them to RTMP while mixing in looping background audio

## Quick Start

**1. Configure `.env`:**
```bash
cp .env.example .env
```
Edit `.env`:
```bash
VIDEO_FOLDER=/path/to/your/videos

# Optional: folder of MP3s to play as continuous background audio
# Leave empty for a silent stream
AUDIO_FOLDER=/path/to/your/music

SEGMENT_DURATION=5  # seconds per clip
PORT=8081           # Flask API port
```

**2. Start:**
```bash
docker compose up -d
```

**3. Watch:**
| URL | Purpose |
|-----|---------|
| `http://server-ip:8080/hls/stream.m3u8` | **Live HLS stream** (VLC, Safari, TV apps) |
| `http://server-ip:8081/iptv.m3u` | IPTV playlist (points to the HLS stream) |
| `http://server-ip:8081/api/status` | Server status |
| `http://server-ip:8081/api/stream-status` | Clip pusher status |

## Samsung / TV Setup

1. Install an IPTV app (e.g. SS IPTV, TiviMate, Smart IPTV)
2. Add playlist URL: `http://server-ip:8081/iptv.m3u`

The IPTV playlist points to the live HLS stream automatically.

## Configuration

The system is configured via environment variables in the `.env` file and service definitions in `docker-compose.yml`.

### 1. Streamer & API Configuration (`random-video-streamer`)

These variables control the Flask API and the RTMP clip pusher.

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8081` | Host port for the Flask API and IPTV playlist |
| `VIDEO_FOLDER` | `/videos` | Source video directory (mount in Compose) |
| `AUDIO_FOLDER` | `/audio` | Background MP3 directory. If empty, uses video audio. |
| `CHUNK_FOLDER` | `/chunks` | Directory where `.mp4` chunks are read from |
| `DB_PATH` | `/app/data/segments.db` | SQLite database for tracking played clips |
| `RTMP_URL` | `rtmp://nginx-rtmp:1935/live/stream` | Internal target for the RTMP stream |

### 2. Chunk Generator Configuration (`chunk-generator`)

These variables control how new video chunks are created from your library.

| Variable | Default | Description |
|----------|---------|-------------|
| `CHUNK_DURATION` | `300` | Target length of a single consolidated chunk (seconds) |
| `CLIP_MIN` | `6` | Minimum length of an individual clip within a chunk |
| `CLIP_MAX` | `6` | Maximum length of an individual clip within a chunk |
| `CHUNKS_PER_RUN` | `4` | How many chunks to generate per execution |
| `MAX_CHUNKS` | `56` | Max number of chunks to keep before pruning oldest |
| `VIDEO_DIR` | `/videos` | Where the generator searches for `.mp4`, `.mkv`, `.avi` |
| `OUTPUT_DIR` | `/chunks` | Where the generator writes the final chunks |

## Hardware Requirements

### GPU Acceleration (NVIDIA)
The **Chunk Generator** is optimized for NVIDIA hardware using `h264_nvenc`.
- **Drivers**: Host must have NVIDIA drivers installed.
- **Docker**: `nvidia-container-toolkit` must be installed on the host.
- **Resources**: The `docker-compose.yml` is configured to reserve 1 NVIDIA GPU.

If you do NOT have an NVIDIA GPU, you must edit `generate_chunk.sh` to use `libx264` instead of `h264_nvenc`.

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | Service info & version |
| GET | `/api/status` | Full server status & config overview |
| GET | `/api/stream-status` | RTMP pusher & current audio/chunk info |
| GET | `/iptv.m3u` | IPTV playlist (M3U) for external players |
| POST | `/api/reset` | (N/A) Tracking is currently managed by SQLite |

## Troubleshooting

**Stream not starting / HLS 404**  
The stream takes ~10 seconds to appear after startup. The app waits for `nginx-rtmp` to be healthy before pushing.

**Check logs:**
```bash
docker compose logs -f random-video-streamer   # Clip pusher & API logs
docker compose logs -f chunk-generator         # Encoding progress logs
docker compose logs -f nginx-rtmp              # HLS server logs
```

## Scripts

- `scripts/setup.sh` — initial setup and environment check
- `scripts/start.sh` — start the streaming server

## License

MIT
