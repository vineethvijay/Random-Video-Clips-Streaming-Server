#!/bin/bash
set -e

# If CRON_SCHEDULE is set, install cron job to trigger chunk generation
if [ -n "${CRON_SCHEDULE}" ]; then
  echo "[chunk-gen] Installing cron: ${CRON_SCHEDULE} -> trigger generation"
  (crontab -l 2>/dev/null | grep -v "trigger_generation"; echo "${CRON_SCHEDULE} touch /chunks/.trigger_generation") | crontab -
  cron
fi

RUN_HISTORY="${STATS_DIR:-/chunks}/.cron_run_history"

echo "[chunk-gen] Ready. Waiting for cron triggers or manual UI triggers..."
while true; do
  if [ -f /chunks/.trigger_generation ]; then
    trigger_type="cron"
    if grep -q "manual" /chunks/.trigger_generation 2>/dev/null; then
      trigger_type="manual"
    fi
    echo "[chunk-gen] Generation triggered! (${trigger_type})"
    echo "$(date -Iseconds) ${trigger_type}" >> "$RUN_HISTORY" 2>/dev/null || true
    rm -f /chunks/.trigger_generation
    /generate_chunk.sh manual
  fi
  sleep 5
done
