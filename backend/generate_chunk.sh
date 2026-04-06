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
DURATION_CACHE=""
MODEL_CACHE=""
cleanup() {
  rm -f "$RUNNING_FILE"
  [ -n "$DURATION_CACHE" ] && rm -f "$DURATION_CACHE"
  [ -n "$MODEL_CACHE" ] && rm -f "$MODEL_CACHE"
}
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

DURATION_CACHE=$(mktemp /tmp/video_durations_XXXX.txt)
MODEL_CACHE=$(mktemp /tmp/video_models_XXXX.txt)
HAS_DRAWTEXT=0
HAS_NVENC=0
NVENC_WARNED=0

if ffmpeg -hide_banner -filters 2>/dev/null | grep -qE '(^| )drawtext( |$)'; then
  HAS_DRAWTEXT=1
fi
if ffmpeg -hide_banner -encoders 2>/dev/null | grep -qE '(^| )h264_nvenc( |$)'; then
  HAS_NVENC=1
fi

get_video_duration() {
  local path="$1"
  local cached
  cached=$(awk -F'\t' -v p="$path" '$1==p { print $2; exit }' "$DURATION_CACHE")
  if [ -n "$cached" ]; then
    echo "$cached"
    return
  fi

  local d
  d=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$path" 2>/dev/null | cut -d. -f1)
  if ! [ "$d" -ge 0 ] 2>/dev/null; then
    d=0
  fi
  printf '%s\t%s\n' "$path" "$d" >> "$DURATION_CACHE"
  echo "$d"
}

get_model_label_cached() {
  local path="$1"
  local cached

  # Cache avoids repeated API hits for the same source in one run.
  cached=$(awk -F'\t' -v p="$path" '$1==p { $1=""; sub(/^\t/, "", $0); print; exit }' "$MODEL_CACHE")
  if [ -n "$cached" ] || awk -F'\t' -v p="$path" '$1==p { found=1 } END { exit(found?0:1) }' "$MODEL_CACHE"; then
    echo "$cached"
    return
  fi

  local model=""
  local meta_script="${VIDEO_METADATA_SCRIPT:-/scripts/video_metadata.py}"
  if [ -f "$meta_script" ]; then
    model=$(python3 "$meta_script" --model-only "$path" 2>/dev/null)
  fi
  model=$(printf '%s' "$model" | tr '\t' ' ')
  printf '%s\t%s\n' "$path" "$model" >> "$MODEL_CACHE"
  echo "$model"
}

escape_drawtext_text() {
  # Escape text for ffmpeg drawtext text='...'
  printf '%s' "$1" | python3 -c "import sys; t=sys.stdin.read().rstrip(); t=t.replace('\\\\','\\\\\\\\').replace(':','\\\\:').replace(\"'\",\"\\\\'\").replace('%','\\\\%').replace(',','\\\\,'); print(t)"
}

format_watermark_label() {
  local label="$1"
  # Keep only the ID/path fragment for known social URLs; no icon/prefix.
  printf '%s' "$label" | python3 -c "import re,sys; s=sys.stdin.read().strip(); s=s.replace('https://','').replace('http://',''); s=re.sub(r'^www\\.', '', s, flags=re.I); s=re.sub(r'^(instagram\\.com|tiktok\\.com)/?', '', s, flags=re.I); print(s.strip('/'))"
}

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

    dur=$(get_video_duration "$file")

    clip_len=$(( RANDOM % (CLIP_MAX - CLIP_MIN + 1) + CLIP_MIN ))
    max_start=$(( dur - clip_len ))
    [ "$max_start" -le 0 ] && continue

    tmp="/tmp/clip_${idx}.mp4"

    # Fetch/cached model for watermark (bottom-left text)
    MODEL_LABEL=$(get_model_label_cached "$file")
    # No TubeArchivist hit → optional env fallback, or test clip always shows something so you can check style/position
    if [ -z "$MODEL_LABEL" ] && [ -n "${WATERMARK_FALLBACK}" ]; then
      MODEL_LABEL="$WATERMARK_FALLBACK"
    fi
    if [ -z "$MODEL_LABEL" ] && [ "$TEST_MODE" = "1" ]; then
      MODEL_LABEL="${WATERMARK_FALLBACK:-Sample watermark}"
    fi
    if [ "$TEST_MODE" = "1" ]; then
      echo "  [test] Watermark text will be: ${MODEL_LABEL:-<empty — no burn-in>}"
    fi

    if [ "$HW_ACCEL" = "nvidia" ] && [ "$HAS_NVENC" = "1" ]; then
      ENCODER_ARGS="-c:v h264_nvenc -preset p4"
    else
      if [ "$HW_ACCEL" = "nvidia" ] && [ "$HAS_NVENC" != "1" ] && [ "$NVENC_WARNED" = "0" ]; then
        echo "Warning: h264_nvenc encoder unavailable. Falling back to libx264."
        NVENC_WARNED=1
      fi
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
        start1=$(python3 "$SEGMENT_TRACKER" pick_record "$USED_SEGMENTS_JSON" "$file" "$dur" "$clip_len" 2>/dev/null || echo "")
        if [ -z "$start1" ] || ! [ "$start1" -ge 0 ] 2>/dev/null || [ "$start1" -gt "$max_start" ] 2>/dev/null; then
          start1=$(( RANDOM % (max_start + 1) ))
          python3 "$SEGMENT_TRACKER" record "$USED_SEGMENTS_JSON" "$file" "$start1" "$(( start1 + clip_len ))" 2>/dev/null || true
        fi
        start2=$(python3 "$SEGMENT_TRACKER" pick_record "$USED_SEGMENTS_JSON" "$file" "$dur" "$clip_len" 2>/dev/null || echo "")
        if [ -z "$start2" ] || ! [ "$start2" -ge 0 ] 2>/dev/null || [ "$start2" -gt "$max_start" ] 2>/dev/null; then
          start2=$(( RANDOM % (max_start + 1) ))
          python3 "$SEGMENT_TRACKER" record "$USED_SEGMENTS_JSON" "$file" "$start2" "$(( start2 + clip_len ))" 2>/dev/null || true
        fi
        start3=$(python3 "$SEGMENT_TRACKER" pick_record "$USED_SEGMENTS_JSON" "$file" "$dur" "$clip_len" 2>/dev/null || echo "")
        if [ -z "$start3" ] || ! [ "$start3" -ge 0 ] 2>/dev/null || [ "$start3" -gt "$max_start" ] 2>/dev/null; then
          start3=$(( RANDOM % (max_start + 1) ))
          python3 "$SEGMENT_TRACKER" record "$USED_SEGMENTS_JSON" "$file" "$start3" "$(( start3 + clip_len ))" 2>/dev/null || true
        fi
      else
        start1=$(( RANDOM % (start1_max + 1) ))
        start2=$(( start2_min + RANDOM % (start2_max - start2_min + 1) ))
        start3=$(( start3_min + RANDOM % (start3_max - start3_min + 1) ))
      fi

      # Build the wall in one pass, then apply a moody + subtle-psychedelic look.
      VF_STACK="[0:v]scale=640:1080:force_original_aspect_ratio=increase,crop=640:1080[v0];[1:v]scale=640:1080:force_original_aspect_ratio=increase,crop=640:1080[v1];[2:v]scale=640:1080:force_original_aspect_ratio=increase,crop=640:1080[v2];[v0][v1][v2]xstack=inputs=3:layout=0_0|w0_0|w0+w1_0[stacked];[stacked]split=2[orig][tmp];[tmp]gblur=sigma=6[blur];[orig][blur]blend=all_mode=screen:all_opacity=0.08,eq=contrast=1.03:brightness=-0.022:saturation=1.09,curves=all='0/0 0.68/0.62 1/0.88',vignette=PI/13,hue=h=5,unsharp=5:5:0.24:5:5:0.0[outf]"
      if [ -n "$MODEL_LABEL" ]; then
        if [ "$HAS_DRAWTEXT" = "1" ]; then
          echo "  Combining + drawtext..."
          WM_LABEL=$(format_watermark_label "$MODEL_LABEL")
          DT_TEXT=$(escape_drawtext_text "$WM_LABEL")
          VF_STACK_WM="${VF_STACK};[outf]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='${DT_TEXT}':fontsize=26:fontcolor=white:box=1:boxcolor=black@0.42:boxborderw=12:x=(640-tw)/2:y=h-th-24:shadowcolor=black@0.65:shadowx=2:shadowy=2[outwm]"
          ffmpeg -hide_banner -y \
            -ss "$start1" -i "$file" \
            -ss "$start2" -i "$file" \
            -ss "$start3" -i "$file" \
            -t "$clip_len" \
            -filter_complex "$VF_STACK_WM" -map "[outwm]" -map "1:a?" \
            $ENCODER_ARGS -b:v 4000k -maxrate 4000k -bufsize 8000k \
            -g 60 -keyint_min 60 \
            -c:a aac -b:a 128k -ar 44100 -ac 2 \
            -movflags +faststart -loglevel error "$tmp" || \
          ffmpeg -hide_banner -y \
            -ss "$start1" -i "$file" \
            -ss "$start2" -i "$file" \
            -ss "$start3" -i "$file" \
            -t "$clip_len" \
            -filter_complex "$VF_STACK_WM" -map "[outwm]" -an \
            $ENCODER_ARGS -b:v 4000k -maxrate 4000k -bufsize 8000k \
            -g 60 -keyint_min 60 \
            -movflags +faststart -loglevel error "$tmp"
        else
          echo "  Combining + ASS watermark..."
          XS_TMP="/tmp/xstack_pre_wm_${idx}.mp4"
          ffmpeg -hide_banner -y \
            -ss "$start1" -i "$file" \
            -ss "$start2" -i "$file" \
            -ss "$start3" -i "$file" \
            -t "$clip_len" \
            -filter_complex "$VF_STACK" -map "[outf]" -map "1:a?" \
            $ENCODER_ARGS -b:v 4000k -maxrate 4000k -bufsize 8000k \
            -g 60 -keyint_min 60 \
            -c:a aac -b:a 128k -ar 44100 -ac 2 \
            -movflags +faststart -loglevel error "$XS_TMP" || \
          ffmpeg -hide_banner -y \
            -ss "$start1" -i "$file" \
            -ss "$start2" -i "$file" \
            -ss "$start3" -i "$file" \
            -t "$clip_len" \
            -filter_complex "$VF_STACK" -map "[outf]" -an \
            $ENCODER_ARGS -b:v 4000k -maxrate 4000k -bufsize 8000k \
            -g 60 -keyint_min 60 \
            -movflags +faststart -loglevel error "$XS_TMP"
          ASS_FILE="/tmp/watermark_${idx}.ass"
          safe_label=$(printf '%s' "$MODEL_LABEL" | python3 -c "import sys; t=sys.stdin.read().rstrip(); print(t.replace('\\\\','\\\\\\\\').replace('{','\\\\{').replace('}','\\\\}'));" 2>/dev/null || echo "$MODEL_LABEL")
          cat > "$ASS_FILE" << ASSEOF
[Script Info]
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Watermark,DejaVu Sans,24,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,-1,0,0,0,100,100,0,0,3,1,1,1,16,16,16,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,99:00:00.00,Watermark,,0,0,0,,{\an2\pos(320,1068)\blur0.6\h\h}${safe_label}
ASSEOF
          ffmpeg -hide_banner -y -i "$XS_TMP" -vf "subtitles=${ASS_FILE}:fontsdir=/usr/share/fonts,format=yuv420p" -map 0:v -map 0:a? -c:v libx264 -preset veryfast -c:a copy -movflags +faststart -loglevel error "$tmp"
          rm -f "$XS_TMP"
        fi
      else
        echo "  Combining..."
        ffmpeg -hide_banner -y \
          -ss "$start1" -i "$file" \
          -ss "$start2" -i "$file" \
          -ss "$start3" -i "$file" \
          -t "$clip_len" \
          -filter_complex "$VF_STACK" -map "[outf]" -map "1:a?" \
          $ENCODER_ARGS -b:v 4000k -maxrate 4000k -bufsize 8000k \
          -g 60 -keyint_min 60 \
          -c:a aac -b:a 128k -ar 44100 -ac 2 \
          -movflags +faststart -loglevel error "$tmp" || \
        ffmpeg -hide_banner -y \
          -ss "$start1" -i "$file" \
          -ss "$start2" -i "$file" \
          -ss "$start3" -i "$file" \
          -t "$clip_len" \
          -filter_complex "$VF_STACK" -map "[outf]" -an \
          $ENCODER_ARGS -b:v 4000k -maxrate 4000k -bufsize 8000k \
          -g 60 -keyint_min 60 \
          -movflags +faststart -loglevel error "$tmp"
      fi
      [ -f "$tmp" ] && echo "file '$tmp'" >> "$CONCAT_LIST" && \
      { fullpath=$(realpath "$file" 2>/dev/null || readlink -f "$file" 2>/dev/null || echo "$file"); [ -n "${VIDEO_HOST_PATH}" ] && fullpath="${fullpath//${VIDEO_DIR}\//${VIDEO_HOST_PATH%/}/}"; SOURCE_BASENAMES="${SOURCE_BASENAMES}${SOURCE_BASENAMES:+
}${fullpath}"; total=$(( total + clip_len )); idx=$(( idx + 1 )); echo "  Segment $idx: ${total}s / ${CHUNK_DURATION}s"; true; }
    else
      # Single-panel: center clip with pad (original behavior)
      start=""
      if command -v python3 >/dev/null 2>&1 && [ -f "$SEGMENT_TRACKER" ]; then
        start=$(python3 "$SEGMENT_TRACKER" pick_record "$USED_SEGMENTS_JSON" "$file" "$dur" "$clip_len" 2>/dev/null || true)
      fi
      if [ -z "$start" ] || ! [ "$start" -ge 0 ] 2>/dev/null || [ "$start" -gt "$max_start" ] 2>/dev/null; then
        start=$(( RANDOM % (max_start + 1) ))
        [ -f "$SEGMENT_TRACKER" ] && python3 "$SEGMENT_TRACKER" record "$USED_SEGMENTS_JSON" "$file" "$start" "$(( start + clip_len ))" 2>/dev/null || true
      fi

      # Single panel look: slightly moodier shadows, a bit more glow, subtle psychedelic hue shift.
      VF_BASE="scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=30,format=yuv420p,split=2[orig][tmp];[tmp]gblur=sigma=6[blur];[orig][blur]blend=all_mode=screen:all_opacity=0.08,eq=contrast=1.03:brightness=-0.022:saturation=1.09,curves=all='0/0 0.68/0.62 1/0.88',vignette=PI/13,hue=h=5,unsharp=5:5:0.24:5:5:0.0"
      if [ -n "$MODEL_LABEL" ]; then
        if [ "$HAS_DRAWTEXT" = "1" ]; then
          WM_LABEL=$(format_watermark_label "$MODEL_LABEL")
          DT_TEXT=$(escape_drawtext_text "$WM_LABEL")
          VF_BASE="${VF_BASE},drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='${DT_TEXT}':fontsize=26:fontcolor=white:box=1:boxcolor=black@0.42:boxborderw=12:x=24:y=h-th-24:shadowcolor=black@0.65:shadowx=2:shadowy=2"
        else
          ASS_FILE="/tmp/watermark_${idx}.ass"
          safe_label=$(printf '%s' "$MODEL_LABEL" | python3 -c "import sys; t=sys.stdin.read().rstrip(); print(t.replace('\\\\','\\\\\\\\').replace('{','\\\\{').replace('}','\\\\}'));" 2>/dev/null || echo "$MODEL_LABEL")
          cat > "$ASS_FILE" << ASSEOF
[Script Info]
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Watermark,DejaVu Sans,24,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,-1,0,0,0,100,100,0,0,3,1,1,1,16,16,16,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,99:00:00.00,Watermark,,0,0,0,,{\an1\pos(20,1068)\blur0.6\h\h}${safe_label}
ASSEOF
          VF_BASE="${VF_BASE},subtitles=${ASS_FILE}:fontsdir=/usr/share/fonts,format=yuv420p"
        fi
      fi

      ffmpeg -hide_banner -y -ss "$start" -i "$file" -t "$clip_len" \
        -vf "$VF_BASE" \
        $ENCODER_ARGS -b:v 4000k -maxrate 4000k -bufsize 8000k \
        -g 60 -keyint_min 60 \
        -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -movflags +faststart \
        -loglevel error "$tmp" && \
      echo "file '$tmp'" >> "$CONCAT_LIST" && \
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
    export VIDEO_METADATA_SCRIPT WATERMARK_FALLBACK
    SOURCES_JSON=$(echo "$SOURCE_BASENAMES" | sort -u | python3 -c "
import sys, json, subprocess, os
paths = [l.strip() for l in sys.stdin if l.strip()]
script = os.environ.get('VIDEO_METADATA_SCRIPT', '/scripts/video_metadata.py')
sources = []
for path in paths:
    model = None
    thumb = None
    title = None
    channel = None
    try:
        out = subprocess.run([sys.executable, script, path], capture_output=True, text=True, timeout=12)
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

  rm -f /tmp/clip_*.mp4 /tmp/watermark_*.ass /tmp/xstack_pre_wm_*.mp4 "$CONCAT_LIST"
  chunk_elapsed=$(($(date +%s)-chunk_start))
  echo "Created: $CHUNK_NAME (total: ${chunk_elapsed}s)"
done
