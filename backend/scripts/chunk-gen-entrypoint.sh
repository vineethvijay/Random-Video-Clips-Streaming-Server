#!/bin/bash
# NOTE: deliberately no `set -e` — ffmpeg inside generate_chunk.sh can SIGABRT
# on rare memory-corruption bugs (NVENC / concat-filter edge cases). We want
# the container to stay up and self-heal so the next trigger works, instead of
# crash-looping and leaving a stale .generation_running lock behind.

# Trigger path: TRIGGER_DIR (named volume) avoids host permission issues; else STATS_DIR or /chunks
TRIGGER_DIR="${TRIGGER_DIR:-${STATS_DIR:-/chunks}}"
TRIGGER_FILE="${TRIGGER_DIR}/.trigger_generation"
TEST_TRIGGER_FILE="${TRIGGER_DIR}/.trigger_test_generation"
TEST_DONE_FILE="${TRIGGER_DIR}/.test_generation_done"
RUNNING_FILE="${TRIGGER_DIR}/.generation_running"

RUN_HISTORY="${STATS_DIR:-/chunks}/.cron_run_history"

# Defensive: if we're starting up and a stale lock exists from a previous crash,
# clear it. (generate_chunk.sh trap cleanup doesn't run on SIGABRT/SIGKILL.)
if [ -f "$RUNNING_FILE" ]; then
  echo "[chunk-gen] Removing stale lock from previous run: $RUNNING_FILE"
  rm -f "$RUNNING_FILE"
fi

run_generation() {
  local mode="$1"
  /generate_chunk.sh "$mode"
  local rc=$?
  # Always scrub the running lock — protects against SIGABRT/OOM/SIGKILL
  # where the bash EXIT trap inside generate_chunk.sh can't fire.
  if [ -f "$RUNNING_FILE" ]; then
    echo "[chunk-gen] Cleaning up lock file after generation (exit=$rc)"
    rm -f "$RUNNING_FILE"
  fi
  return $rc
}

echo "[chunk-gen] Ready. Waiting for host cron or manual UI triggers (${TRIGGER_FILE})..."
while true; do
  # Test generation trigger (10s clip)
  if [ -f "$TEST_TRIGGER_FILE" ]; then
    echo "[chunk-gen] Test generation triggered!"
    rm -f "$TEST_TRIGGER_FILE" "$TEST_DONE_FILE"
    rm -f /chunks/test_clip_10s.mp4
    run_generation test
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
    run_generation manual
  fi
  sleep 5
done
