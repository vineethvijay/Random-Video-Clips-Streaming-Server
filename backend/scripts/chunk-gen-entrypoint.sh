#!/bin/bash
set -e

# Trigger path: TRIGGER_DIR (named volume) avoids host permission issues; else STATS_DIR or /chunks
TRIGGER_DIR="${TRIGGER_DIR:-${STATS_DIR:-/chunks}}"
TRIGGER_FILE="${TRIGGER_DIR}/.trigger_generation"

RUN_HISTORY="${STATS_DIR:-/chunks}/.cron_run_history"

echo "[chunk-gen] Ready. Waiting for host cron or manual UI triggers (${TRIGGER_FILE})..."
while true; do
  if [ -f "$TRIGGER_FILE" ]; then
    trigger_type="cron"
    if grep -q "manual" "$TRIGGER_FILE" 2>/dev/null; then
      trigger_type="manual"
    fi
    echo "[chunk-gen] Generation triggered! (${trigger_type})"
    echo "$(date -Iseconds) ${trigger_type}" >> "$RUN_HISTORY" 2>/dev/null || true
    rm -f "$TRIGGER_FILE"
    /generate_chunk.sh manual
  fi
  sleep 5
done
