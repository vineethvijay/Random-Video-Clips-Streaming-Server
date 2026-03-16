#!/bin/bash
# test mode must run first so it overrides env vars
TEST_MODE=0
if [ "$1" = "test" ]; then
  echo ">>> TEST MODE: single 10s clip → test_clip_10s.mp4 <<<"
  TEST_MODE=1
  export CHUNK_DURATION=10 CLIP_MIN=10 CLIP_MAX=10 CHUNKS_PER_RUN=1
  set -- manual
fi

VIDEO_DIR="${VIDEO_DIR:-/videos}"
OUTPUT_DIR="${OUTPUT_DIR:-/chunks}"
CHUNK_DURATION="${CHUNK_DURATION:-300}"
CLIP_MIN="${CLIP_MIN:-6}"
CLIP_MAX="${CLIP_MAX:-6}"
CHUNKS_PER_RUN="${CHUNKS_PER_RUN:-4}"
MAX_CHUNKS="${MAX_CHUNKS:-56}"
HW_ACCEL="${HW_ACCEL:-none}"
# VIDEO_WALL=1: triple-panel layout (3 portrait clips side-by-side) per segment
VIDEO_WALL="${VIDEO_WALL:-0}"

RUNNING_FILE="$OUTPUT_DIR/.generation_running"
cleanup() { rm -f "$RUNNING_FILE"; }
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"

if [ "$1" != "manual" ]; then
  # Prune oldest chunks if over MAX_CHUNKS
  while [ "$(ls "$OUTPUT_DIR"/*.mp4 2>/dev/null | wc -l)" -ge "$MAX_CHUNKS" ]; do
    oldest=$(ls -t "$OUTPUT_DIR"/*.mp4 | tail -1)
    echo "Pruning old chunk: $oldest"
    base="${oldest%.mp4}"
    rm -f "$oldest" "${base}.meta.json"
  done
else
  [ "$TEST_MODE" = "1" ] && echo "Test mode: single 10s clip → test_clip_10s.mp4" || echo "Manual generation requested. Skipping pruning."
fi

QUEUE_FILE="$OUTPUT_DIR/.video_queue.txt"
CURRENT_VIDEOS=$(mktemp /tmp/current_videos_XXXX.txt)
find "$VIDEO_DIR" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" \) > "$CURRENT_VIDEOS"

if [ ! -s "$CURRENT_VIDEOS" ]; then
  echo "No videos found in $VIDEO_DIR"
  rm -f "$CURRENT_VIDEOS"
  exit 1
fi

if [ ! -f "$QUEUE_FILE" ]; then
  # Initialize queue randomly the first time
  shuf "$CURRENT_VIDEOS" > "$QUEUE_FILE"
else
  TEMP_QUEUE=$(mktemp /tmp/queue_XXXX.txt)
  
  # Keep only videos that still exist in the current directory (preserve LRU order)
  while IFS= read -r v; do
    if grep -Fxq "$v" "$CURRENT_VIDEOS"; then
      echo "$v" >> "$TEMP_QUEUE"
    fi
  done < "$QUEUE_FILE"
  
  # Insert new videos at random positions (fair chance to appear soon)
  while IFS= read -r v; do
    if ! grep -Fxq "$v" "$TEMP_QUEUE"; then
      count=$(wc -l < "$TEMP_QUEUE")
      pos=$(( count > 0 ? RANDOM % (count + 1) : 0 ))
      { head -n "$pos" "$TEMP_QUEUE"; echo "$v"; tail -n +$(( pos + 1 )) "$TEMP_QUEUE" 2>/dev/null; } > "${TEMP_QUEUE}.2"
      mv "${TEMP_QUEUE}.2" "$TEMP_QUEUE"
    fi
  done < "$CURRENT_VIDEOS"
  
  mv "$TEMP_QUEUE" "$QUEUE_FILE"
fi
rm -f "$CURRENT_VIDEOS"

touch "$RUNNING_FILE"

# Persistent stats dir: mount this so hours played / chunks ever created survive new deployments (optional)
STATS_DIR="${STATS_DIR:-$OUTPUT_DIR}"
mkdir -p "$STATS_DIR"

# Used-segments JSON: track which time ranges we've used per video so we pick new timeframes next time
USED_SEGMENTS_JSON="${STATS_DIR}/.used_segments.json"
SEGMENT_TRACKER="${SEGMENT_TRACKER:-/scripts/segment_tracker.py}"

# Generate CHUNKS_PER_RUN chunks
STOP_FILE="$OUTPUT_DIR/.stop_generation"
CHUNKS_CREATED_FILE="${STATS_DIR}/.chunks_created_total"
for i in $(seq 1 "$CHUNKS_PER_RUN"); do
  if [ -f "$STOP_FILE" ]; then
    echo "Stop requested. Halting chunk generation."
    rm -f "$STOP_FILE"
    exit 0
  fi
  chunk_start=$(date +%s)
  echo "--- Generating chunk $i of $CHUNKS_PER_RUN ---"
  CONCAT_LIST=$(mktemp /tmp/concat_XXXX.txt)
  total=0
  idx=0
  SOURCE_BASENAMES=""

  while [ "$total" -lt "$CHUNK_DURATION" ]; do
    if [ -f "$STOP_FILE" ]; then
      echo "Stop requested. Halting chunk generation."
      rm -f "$STOP_FILE"
      exit 0
    fi
    file=$(head -n 1 "$QUEUE_FILE")
    [ -z "$file" ] && echo "No videos found in queue" && break

    echo "  Processing: $(basename "$file")..."

    # Move selected video to the bottom of the queue to ensure least-recently-used
    tail -n +2 "$QUEUE_FILE" > "${QUEUE_FILE}.tmp"
    echo "$file" >> "${QUEUE_FILE}.tmp"
    mv "${QUEUE_FILE}.tmp" "$QUEUE_FILE"

    dur=$(ffprobe -v error -show_entries format=duration \
      -of default=noprint_wrappers=1:nokey=1 "$file" | cut -d. -f1)

    clip_len=$(( RANDOM % (CLIP_MAX - CLIP_MIN + 1) + CLIP_MIN ))
    max_start=$(( dur - clip_len ))
    [ "$max_start" -le 0 ] && continue

    tmp="/tmp/clip_${idx}.mp4"

    # Fetch model for watermark (bottom-left text)
    MODEL_LABEL=""
    if [ -n "${TUBEARCHIVIST_URL}" ] && [ -n "${TUBEARCHIVIST_TOKEN}" ] && [ -f "${TUBEARCHIVIST_SCRIPT:-/scripts/tubearchivist_metadata.py}" ]; then
      MODEL_LABEL=$(python3 "${TUBEARCHIVIST_SCRIPT:-/scripts/tubearchivist_metadata.py}" --model-only "${TUBEARCHIVIST_URL}" "${TUBEARCHIVIST_TOKEN}" "$file" 2>/dev/null)
    fi

    if [ "$HW_ACCEL" = "nvidia" ]; then
      ENCODER_ARGS="-c:v h264_nvenc -preset p4"
    else
      ENCODER_ARGS="-c:v libx264 -preset veryfast"
    fi

    if [ "$VIDEO_WALL" = "1" ]; then
      # Triple-panel video wall: 3 clips from same source, 640x1080 each, hstack to 1920x1080
      # Extract-then-combine: -ss before -i = fast seek. Trim reads whole file = very slow.
      # Segment tracker: pick 3 unused ranges from whole video (no zone/panel distinction). Record after each pick so next pick avoids overlap.
      echo "  Segment $((idx+1)) starting..."
      max_start=$(( dur - clip_len ))
      [ "$max_start" -lt 0 ] && max_start=0
      zone=$(( dur / 3 ))
      [ "$zone" -lt "$clip_len" ] && zone=$clip_len
      start1_max=$(( zone - clip_len )); [ "$start1_max" -lt 0 ] && start1_max=0
      start2_min=$zone; start2_max=$(( zone * 2 - clip_len )); [ "$start2_max" -lt "$start2_min" ] && start2_max=$start2_min
      start3_min=$(( zone * 2 )); start3_max=$(( dur - clip_len )); [ "$start3_max" -lt "$start3_min" ] && start3_max=$start3_min

      start1=""; start2=""; start3=""
      if command -v python3 >/dev/null 2>&1 && [ -f "$SEGMENT_TRACKER" ]; then
        start1=$(python3 "$SEGMENT_TRACKER" pick "$USED_SEGMENTS_JSON" "$file" "$dur" "$clip_len" 2>/dev/null || echo "")
        [ -z "$start1" ] || ! [ "$start1" -ge 0 ] 2>/dev/null || [ "$start1" -gt "$max_start" ] 2>/dev/null && start1=$(( RANDOM % (max_start + 1) ))
        python3 "$SEGMENT_TRACKER" record "$USED_SEGMENTS_JSON" "$file" "$start1" "$(( start1 + clip_len ))" 2>/dev/null || true
        start2=$(python3 "$SEGMENT_TRACKER" pick "$USED_SEGMENTS_JSON" "$file" "$dur" "$clip_len" 2>/dev/null || echo "")
        [ -z "$start2" ] || ! [ "$start2" -ge 0 ] 2>/dev/null || [ "$start2" -gt "$max_start" ] 2>/dev/null && start2=$(( RANDOM % (max_start + 1) ))
        python3 "$SEGMENT_TRACKER" record "$USED_SEGMENTS_JSON" "$file" "$start2" "$(( start2 + clip_len ))" 2>/dev/null || true
        start3=$(python3 "$SEGMENT_TRACKER" pick "$USED_SEGMENTS_JSON" "$file" "$dur" "$clip_len" 2>/dev/null || echo "")
        [ -z "$start3" ] || ! [ "$start3" -ge 0 ] 2>/dev/null || [ "$start3" -gt "$max_start" ] 2>/dev/null && start3=$(( RANDOM % (max_start + 1) ))
      else
        start1=$(( RANDOM % (start1_max + 1) ))
        start2=$(( start2_min + RANDOM % (start2_max - start2_min + 1) ))
        start3=$(( start3_min + RANDOM % (start3_max - start3_min + 1) ))
      fi
      end1=$(( start1 + clip_len ))
      end2=$(( start2 + clip_len ))
      end3=$(( start3 + clip_len ))

      W1="/tmp/wall_${idx}_1.mp4"
      W2="/tmp/wall_${idx}_2.mp4"
      W3="/tmp/wall_${idx}_3.mp4"
      VF_PANEL="scale=640:1080:force_original_aspect_ratio=increase,crop=640:1080,fps=30,format=yuv420p"
      echo "  Panel 1/3..." && ffmpeg -hide_banner -y -ss "$start1" -i "$file" -t "$clip_len" -vf "$VF_PANEL" $ENCODER_ARGS -b:v 4000k -an -movflags +faststart -loglevel error "$W1" && \
      echo "  Panel 2/3..." && ( ffmpeg -hide_banner -y -ss "$start2" -i "$file" -t "$clip_len" -vf "$VF_PANEL" $ENCODER_ARGS -b:v 4000k -c:a aac -b:a 128k -ar 44100 -ac 2 -movflags +faststart -loglevel error "$W2" 2>/dev/null || ffmpeg -hide_banner -y -ss "$start2" -i "$file" -t "$clip_len" -vf "$VF_PANEL" $ENCODER_ARGS -b:v 4000k -an -movflags +faststart -loglevel error "$W2" ) && \
      echo "  Panel 3/3..." && ffmpeg -hide_banner -y -ss "$start3" -i "$file" -t "$clip_len" -vf "$VF_PANEL" $ENCODER_ARGS -b:v 4000k -an -movflags +faststart -loglevel error "$W3" && \
      echo "  Combining..." && \
      ( if [ -n "$MODEL_LABEL" ]; then
          ASS_FILE="/tmp/watermark_${idx}.ass"
          safe_label=$(printf '%s' "$MODEL_LABEL" | python3 -c "import sys; t=sys.stdin.read().rstrip(); print(t.replace('\\\\','\\\\\\\\').replace('{','\\\\{').replace('}','\\\\}'));" 2>/dev/null || echo "$MODEL_LABEL")
          cat > "$ASS_FILE" << ASSEOF
[Script Info]
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Watermark,DejaVu Sans,22,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,2,1,1,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,99:00:00.00,Watermark,,0,0,0,,{\an1\pos(10,1000)}${safe_label}
ASSEOF
          VF_COMB="[0:v]scale=640:1080:force_original_aspect_ratio=increase,crop=640:1080[v0];[1:v]scale=640:1080:force_original_aspect_ratio=increase,crop=640:1080[v1];[2:v]scale=640:1080:force_original_aspect_ratio=increase,crop=640:1080[v2];[v0][v1][v2]xstack=inputs=3:layout=0_0|w0_0|w0+w1_0[outv];[outv]subtitles=${ASS_FILE}[outf]"
          MAP_V="[outf]"
        else
          VF_COMB="[0:v]scale=640:1080:force_original_aspect_ratio=increase,crop=640:1080[v0];[1:v]scale=640:1080:force_original_aspect_ratio=increase,crop=640:1080[v1];[2:v]scale=640:1080:force_original_aspect_ratio=increase,crop=640:1080[v2];[v0][v1][v2]xstack=inputs=3:layout=0_0|w0_0|w0+w1_0[outf]"
          MAP_V="[outf]"
        fi
        ffmpeg -hide_banner -y -i "$W1" -i "$W2" -i "$W3" -filter_complex "$VF_COMB" -map "$MAP_V" -map '1:a?' -c:v libx264 -preset veryfast -c:a aac -b:a 128k -ar 44100 -ac 2 -movflags +faststart -loglevel error "$tmp" 2>/dev/null || \
        ffmpeg -hide_banner -y -i "$W1" -i "$W2" -i "$W3" -filter_complex "$VF_COMB" -map "$MAP_V" -an -c:v libx264 -preset veryfast -movflags +faststart -loglevel error "$tmp"
      ) && rm -f "$W1" "$W2" "$W3" && \
      echo "file '$tmp'" >> "$CONCAT_LIST" && \
      { [ -f "$SEGMENT_TRACKER" ] && python3 "$SEGMENT_TRACKER" record "$USED_SEGMENTS_JSON" "$file" "$start1" "$end1" 2>/dev/null; python3 "$SEGMENT_TRACKER" record "$USED_SEGMENTS_JSON" "$file" "$start2" "$end2" 2>/dev/null; python3 "$SEGMENT_TRACKER" record "$USED_SEGMENTS_JSON" "$file" "$start3" "$end3" 2>/dev/null; true; } && \
      { fullpath=$(realpath "$file" 2>/dev/null || readlink -f "$file" 2>/dev/null || echo "$file"); [ -n "${VIDEO_HOST_PATH}" ] && fullpath="${fullpath//${VIDEO_DIR}\//${VIDEO_HOST_PATH%/}/}"; SOURCE_BASENAMES="${SOURCE_BASENAMES}${SOURCE_BASENAMES:+
}${fullpath}"; total=$(( total + clip_len )); idx=$(( idx + 1 )); echo "  Segment $idx: ${total}s / ${CHUNK_DURATION}s"; true; }
    else
      # Single-panel: center clip with pad (original behavior)
      start=""
      if command -v python3 >/dev/null 2>&1 && [ -f "$SEGMENT_TRACKER" ]; then
        start=$(python3 "$SEGMENT_TRACKER" pick "$USED_SEGMENTS_JSON" "$file" "$dur" "$clip_len" 2>/dev/null || true)
      fi
      if [ -z "$start" ] || ! [ "$start" -ge 0 ] 2>/dev/null || [ "$start" -gt "$max_start" ] 2>/dev/null; then
        start=$(( RANDOM % (max_start + 1) ))
      fi

      VF_BASE="scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=30,format=yuv420p"
      if [ -n "$MODEL_LABEL" ]; then
        ASS_FILE="/tmp/watermark_${idx}.ass"
        safe_label=$(printf '%s' "$MODEL_LABEL" | python3 -c "import sys; t=sys.stdin.read().rstrip(); print(t.replace('\\\\','\\\\\\\\').replace('{','\\\\{').replace('}','\\\\}'));" 2>/dev/null || echo "$MODEL_LABEL")
        cat > "$ASS_FILE" << ASSEOF
[Script Info]
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Watermark,DejaVu Sans,22,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,2,1,1,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,99:00:00.00,Watermark,,0,0,0,,{\an1\pos(10,1000)}${safe_label}
ASSEOF
        VF_BASE="${VF_BASE},subtitles=${ASS_FILE}"
      fi

      ffmpeg -hide_banner -y -ss "$start" -i "$file" -t "$clip_len" \
        -vf "$VF_BASE" \
        $ENCODER_ARGS -b:v 4000k -maxrate 4000k -bufsize 8000k \
        -g 60 -keyint_min 60 \
        -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -movflags +faststart \
        -loglevel error "$tmp" && \
      echo "file '$tmp'" >> "$CONCAT_LIST" && \
      { [ -f "$SEGMENT_TRACKER" ] && python3 "$SEGMENT_TRACKER" record "$USED_SEGMENTS_JSON" "$file" "$start" "$(( start + clip_len ))" 2>/dev/null || true; } && \
      { fullpath=$(realpath "$file" 2>/dev/null || readlink -f "$file" 2>/dev/null || echo "$file"); [ -n "${VIDEO_HOST_PATH}" ] && fullpath="${fullpath//${VIDEO_DIR}\//${VIDEO_HOST_PATH%/}/}"; SOURCE_BASENAMES="${SOURCE_BASENAMES}${SOURCE_BASENAMES:+
}${fullpath}"; total=$(( total + clip_len )); idx=$(( idx + 1 )); echo "  Segment $idx: ${total}s / ${CHUNK_DURATION}s"; true; }
    fi
  done

  # Friendly chunk names: <star>_<random_word>_<date>.mp4 (e.g. sirius_portcullis_2025-03-08.mp4)
  if [ "$TEST_MODE" = "1" ]; then
    CHUNK_BASE="test_clip_10s"
    CHUNK_NAME="$OUTPUT_DIR/${CHUNK_BASE}.mp4"
  else
    STARS=(sirius canopus arcturus vega capella rigel procyon betelgeuse altair aldebaran spica antares pollux fomalhaut deneb regulus castor bellatrix alnilam alnitak mintaka algieba alpheratz algol mirfak dubhe merak phecda megrez alioth mizar alkaid enif scheat markab sadalmelik skat rasalhague cebalrai zubenelgenubi zubeneschamali unukalhai kornephoros sadachbia schedar algenib alcor achernar hamal diphda)
    word1=${STARS[$((RANDOM % ${#STARS[@]}))]}
    word2=$(curl -sf --connect-timeout 3 --max-time 5 "https://random-word-api.herokuapp.com/word" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)[0])" 2>/dev/null)
    [ -z "$word2" ] && FALLBACK=(portcullis oversteps mango peach apricot cherry plum citrus honeydew crimson) && word2=${FALLBACK[$((RANDOM % ${#FALLBACK[@]}))]}
    CHUNK_DATE=$(date +%Y-%m-%d)
    CHUNK_BASE="${word1}_${word2}_${CHUNK_DATE}"
    CHUNK_NAME="$OUTPUT_DIR/${CHUNK_BASE}.mp4"
    # Avoid overwrite if same second (e.g. fast runs)
    while [ -f "$CHUNK_NAME" ]; do
      CHUNK_BASE="${word1}_${word2}_${CHUNK_DATE}_${RANDOM}"
      CHUNK_NAME="$OUTPUT_DIR/${CHUNK_BASE}.mp4"
    done
  fi
  ffmpeg -y -f concat -safe 0 -i "$CONCAT_LIST" \
    -c copy "$CHUNK_NAME" -loglevel error

  # Write metadata: source videos (full paths + model per source), codec, resolution (for dashboard)
  META_FILE="$OUTPUT_DIR/${CHUNK_BASE}.meta.json"
  SOURCES_JSON="[]"
  if [ -n "$SOURCE_BASENAMES" ]; then
    export TUBEARCHIVIST_URL TUBEARCHIVIST_TOKEN TUBEARCHIVIST_SCRIPT
    SOURCES_JSON=$(echo "$SOURCE_BASENAMES" | sort -u | python3 -c "
import sys, json, subprocess, os
paths = [l.strip() for l in sys.stdin if l.strip()]
tube_url = (os.environ.get('TUBEARCHIVIST_URL') or '').strip().rstrip('/')
tube_token = (os.environ.get('TUBEARCHIVIST_TOKEN') or '').strip()
script = os.environ.get('TUBEARCHIVIST_SCRIPT', '/scripts/tubearchivist_metadata.py')
sources = []
for path in paths:
    model = None
    thumb = None
    title = None
    channel = None
    if tube_url and tube_token:
        try:
            out = subprocess.run([sys.executable, script, tube_url, tube_token, path], capture_output=True, text=True, timeout=12)
            if out.returncode == 0:
                d = json.loads(out.stdout or '{}')
                model = d.get('model_info')
                thumb = d.get('thumbnail_url')
                title = d.get('title')
                channel = d.get('channel')
        except: pass
    sources.append({'path': path, 'model': model, 'thumbnail_url': thumb, 'title': title, 'channel': channel})
print(json.dumps(sources))
" 2>/dev/null)
    if [ -z "$SOURCES_JSON" ] || [ "$SOURCES_JSON" = "[]" ]; then
      SOURCES_JSON=$(echo "$SOURCE_BASENAMES" | sort -u | python3 -c "import sys,json; print(json.dumps([{'path': l.strip(), 'model': None, 'thumbnail_url': None, 'title': None, 'channel': None} for l in sys.stdin if l.strip()]))" 2>/dev/null) || SOURCES_JSON="[]"
    fi
  fi

  # model_info = unique models from sources (for Models button)
  MODEL_JSON=$(echo "$SOURCES_JSON" | python3 -c "import sys,json; s=json.load(sys.stdin); m= sorted(set(x.get('model') for x in s if x.get('model'))); print(json.dumps(m))" 2>/dev/null) || MODEL_JSON="[]"

  VIDEO_EXTRA=""
  if codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$CHUNK_NAME" 2>/dev/null) && \
     width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$CHUNK_NAME" 2>/dev/null) && \
     height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$CHUNK_NAME" 2>/dev/null); then
    VIDEO_EXTRA=", \"video_codec\": \"$codec\", \"width\": $width, \"height\": $height"
  fi
  echo "{\"source_videos\": $SOURCES_JSON, \"model_info\": $MODEL_JSON, \"created_at\": \"$(date -Iseconds)\"$VIDEO_EXTRA}" > "$META_FILE"

  # Persist "chunks ever created" count
  count=0
  [ -f "$CHUNKS_CREATED_FILE" ] && count=$(cat "$CHUNKS_CREATED_FILE")
  echo $(( count + 1 )) > "$CHUNKS_CREATED_FILE"

  rm -f /tmp/clip_*.mp4 /tmp/watermark_*.ass "$CONCAT_LIST"
  chunk_elapsed=$(($(date +%s)-chunk_start))
  echo "Created: $CHUNK_NAME (total: ${chunk_elapsed}s)"
done
