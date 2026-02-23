#!/bin/bash
VIDEO_DIR="${VIDEO_DIR:-/videos}"
OUTPUT_DIR="${OUTPUT_DIR:-/chunks}"
CHUNK_DURATION="${CHUNK_DURATION:-300}"
CLIP_MIN="${CLIP_MIN:-6}"
CLIP_MAX="${CLIP_MAX:-6}"
CHUNKS_PER_RUN="${CHUNKS_PER_RUN:-4}"
MAX_CHUNKS="${MAX_CHUNKS:-56}"

mkdir -p "$OUTPUT_DIR"

# Prune oldest chunks if over MAX_CHUNKS
while [ "$(ls "$OUTPUT_DIR"/*.mp4 2>/dev/null | wc -l)" -ge "$MAX_CHUNKS" ]; do
  oldest=$(ls -t "$OUTPUT_DIR"/*.mp4 | tail -1)
  echo "Pruning old chunk: $oldest"
  rm -f "$oldest"
done

# Generate CHUNKS_PER_RUN chunks
for i in $(seq 1 "$CHUNKS_PER_RUN"); do
  echo "--- Generating chunk $i of $CHUNKS_PER_RUN ---"
  CONCAT_LIST=$(mktemp /tmp/concat_XXXX.txt)
  total=0
  idx=0

  while [ "$total" -lt "$CHUNK_DURATION" ]; do
    file=$(find "$VIDEO_DIR" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" \) | shuf -n 1)
    [ -z "$file" ] && echo "No videos found" && exit 1

    dur=$(ffprobe -v error -show_entries format=duration \
      -of default=noprint_wrappers=1:nokey=1 "$file" | cut -d. -f1)

    clip_len=$(( RANDOM % (CLIP_MAX - CLIP_MIN + 1) + CLIP_MIN ))
    max_start=$(( dur - clip_len ))
    [ "$max_start" -le 0 ] && continue

    start=$(( RANDOM % max_start ))
    tmp="/tmp/clip_${idx}.mp4"

    ffmpeg -hide_banner -y -ss "$start" -i "$file" -t "$clip_len" \
      -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=30,format=yuv420p" \
      -c:v h264_nvenc -preset p4 -b:v 4000k -maxrate 4000k -bufsize 8000k \
      -g 60 -keyint_min 60 \
      -c:a aac -b:a 128k -ar 44100 -ac 2 \
      -movflags +faststart \
      -loglevel error "$tmp" && \
      echo "file '$tmp'" >> "$CONCAT_LIST"

    total=$(( total + clip_len ))
    idx=$(( idx + 1 ))
  done

  CHUNK_NAME="$OUTPUT_DIR/chunk_$(date +%s).mp4"
  ffmpeg -y -f concat -safe 0 -i "$CONCAT_LIST" \
    -c copy "$CHUNK_NAME" -loglevel error

  rm -f /tmp/clip_*.mp4 "$CONCAT_LIST"
  echo "Created: $CHUNK_NAME"
done
