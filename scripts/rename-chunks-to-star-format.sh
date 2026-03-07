#!/bin/bash
# Rename existing chunk files to the new format: <star>_<word>_<date>.mp4 (date only, no time)
# Uses file mtime for the date part. Pairs .meta.json files are renamed too.
#
# Usage: ./rename-chunks-to-star-format.sh [chunks_dir]
#   chunks_dir: from CHUNK_FOLDER env, or first arg, or ./chunks
#
# On Proxmox (if CHUNK_FOLDER in .env differs from ./chunks):
#   source .env 2>/dev/null; ./scripts/rename-chunks-to-star-format.sh
#   or: ./scripts/rename-chunks-to-star-format.sh /root/HDD_INT/tube_archiver-chunks

[ -f .env ] && set -a && source .env 2>/dev/null && set +a
CHUNKS_DIR="${CHUNK_FOLDER:-${1:-./chunks}}"
[ ! -d "$CHUNKS_DIR" ] && { echo "Directory not found: $CHUNKS_DIR"; echo "  Set CHUNK_FOLDER or pass path as first arg."; exit 1; }

STARS=(sirius canopus arcturus vega capella rigel procyon betelgeuse altair aldebaran spica antares pollux fomalhaut deneb regulus castor bellatrix alnilam alnitak mintaka algieba alpheratz algol mirfak dubhe merak phecda megrez alioth mizar alkaid enif scheat markab sadalmelik skat rasalhague cebalrai zubenelgenubi zubeneschamali unukalhai kornephoros sadachbia schedar algenib alcor achernar hamal diphda)
WORDS=(portcullis oversteps mango peach apricot cherry plum citrus honeydew crimson)

for f in "$CHUNKS_DIR"/*.mp4; do
  [ -f "$f" ] || continue
  base_old="${f%.mp4}"
  meta_old="${base_old}.meta.json"

  star="${STARS[$((RANDOM % ${#STARS[@]}))]}"
  word="${WORDS[$((RANDOM % ${#WORDS[@]}))]}"
  # Use file mtime for date (preserves "created" feel)
  if date_cmd=$(stat -f "%Sm" -t "%Y-%m-%d" "$f" 2>/dev/null); then
    chunk_date="$date_cmd"
  elif date_cmd=$(stat -c "%y" "$f" 2>/dev/null); then
    chunk_date=$(echo "$date_cmd" | cut -d' ' -f1)
  else
    chunk_date=$(date +%Y-%m-%d)
  fi

  new_base="${star}_${word}_${chunk_date}"
  new_mp4="$CHUNKS_DIR/${new_base}.mp4"
  new_meta="$CHUNKS_DIR/${new_base}.meta.json"

  # Avoid overwrite
  while [ -f "$new_mp4" ]; do
    new_base="${star}_${word}_${chunk_date}_${RANDOM}"
    new_mp4="$CHUNKS_DIR/${new_base}.mp4"
    new_meta="$CHUNKS_DIR/${new_base}.meta.json"
  done

  mv "$f" "$new_mp4" && echo "  $f -> $(basename "$new_mp4")"
  [ -f "$meta_old" ] && mv "$meta_old" "$new_meta" && echo "    + $(basename "$meta_old") -> $(basename "$new_meta")"
done

echo "Done."
