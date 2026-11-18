#!/usr/bin/env bash
# Exits 0 once the keyboard and mouse have been idle for N minutes (default 10), or 1 after the time limit (default 8 h).
# Run it with run_in_background before any step that has to use the screen (human, Chrome's Task Manager).
set -u
need=$(( ${1:-10} * 60 )); end=$(( SECONDS + ${2:-8} * 3600 ))
while [ $SECONDS -lt $end ]; do
  i=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
  [ "${i:-0}" -ge "$need" ] && { echo "$(date +%T) away: idle ${i}s"; exit 0; }
  sleep 60
done
echo "never away for $(( need / 60 )) minutes"; exit 1
