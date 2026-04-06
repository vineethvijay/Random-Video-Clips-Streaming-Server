#!/bin/bash
set -e

# Trigger path: TRIGGER_DIR (named volume) avoids host permission issues; else STATS_DIR or /chunks
TRIGGER_DIR="${TRIGGER_DIR:-${STATS_DIR:-/chunks}}"
TRIGGER_FILE="${TRIGGER_DIR}/.trigger_generation"
TEST_TRIGGER_FILE="${TRIGGER_DIR}/.trigger_test_generation"
TEST_DONE_FILE="${TRIGGER_DIR}/.test_generation_done"

RUN_HISTORY="${STATS_DIR:-/chunks}/.cron_run_history"

echo "[chunk-gen] Ready. Waiting for host cron or manual UI triggers (${TRIGGER_FILE})..."
while true; do
  # Test generation trigger (10s clip)
  if [ -f "$TEST_TRIGGER_FILE" ]; then
    echo "[chunk-gen] Test generation triggered!"
    rm -f "$TEST_TRIGGER_FILE" "$TEST_DONE_FILE"
    rm -f /chunks/test_clip_10s.mp4
    /generate_chunk.sh test
    # Signal completion
    if [ -f /chunks/test_clip_10s.mp4 ]; then
      echo "ok" > "$TEST_DONE_FILE"
    else
      echo "fail" > "$TEST_DONE_FILE"
    fi
    echo "[chunk-gen] Test generation done."
  fi
  # Normal generation trigger
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
