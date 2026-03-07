#!/bin/bash
set -e

# If CRON_SCHEDULE is set, install cron job to trigger chunk generation
if [ -n "${CRON_SCHEDULE}" ]; then
  echo "[chunk-gen] Installing cron: ${CRON_SCHEDULE} -> trigger generation"
  (crontab -l 2>/dev/null | grep -v "trigger_generation"; echo "${CRON_SCHEDULE} touch /chunks/.trigger_generation") | crontab -
  cron
fi

echo "[chunk-gen] Ready. Waiting for cron triggers or manual UI triggers..."
while true; do
  if [ -f /chunks/.trigger_generation ]; then
    echo '[chunk-gen] Generation triggered!'
    rm -f /chunks/.trigger_generation
    /generate_chunk.sh manual
  fi
  sleep 5
done
