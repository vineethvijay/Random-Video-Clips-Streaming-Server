# Video Chunk Generation Implementation Plan

## Goal Description
The user wants to transition from real-time live clip generation to a chunk-based pregeneration approach.
We will schedule a daily job to generate 5-minute video chunks, and have the stream app continuously loop/shuffle through these chunks. The chunks will normalize video characteristics and avoid the stuttering issues caused by concatenating heterogeneous clips in real time.

## Proposed Changes

### docker-compose.yml
- Add `chunk-generator` service using `linuxserver/ffmpeg`
  - Mounts `/videos` and `./chunks` and a generator script `./generate_chunk.sh`
  - Takes env vars for clip duration and pruning rules.
  - Sleeps 24h between generations.
- Modify `random-video-streamer` service
  - Mounts `./chunks`
  - Removes the `nginx-rtmp` dependency since it doesn't need to push anymore.
  - Exposes port 8080 or 8081 for direct HLS or whatever streaming method we decide to keep from the Python app. Actually wait, if the goal is to just play chunks... We should see what the updated Python code should look like.

### generate_chunk.sh
- [NEW] Script to select random clips, re-encode them to identical specs, and concatenate them into a 5-minute chunk.
- Includes logic to prune old chunks when the limit is reached.

### app.py & clip_pusher.py
- [MODIFY] The Python app needs to stream pre-generated chunks instead of dynamically building playlists.
- We need to review how the continuous streaming works if `nginx-rtmp` is retained or if the Python app directly streams the chunks using a loop.

## Verification Plan
### Automated Tests
- Run `docker-compose up -d --build` and verify the containers start successfully.
- Trigger `generate_chunk.sh` manually once to verify it properly encodes and generates a chunk in the `./chunks/` directory.

### Manual Verification
- Stream playback: Access the stream URL (e.g., VLC or browser HLS) to ensure the chunks are being played smoothly without stuttering between clips.
- Log check: Ensure the Python streamer app correctly rotates and loops through the chunks using `docker-compose logs random-video-streamer -f`.
