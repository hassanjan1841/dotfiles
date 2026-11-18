#!/usr/bin/env bash
# Logs battery %, power source, front app, load and the top 5 energy users every 10 minutes until HH:MM (default 02:00).
# usage: battery-log.sh [HH:MM] [logfile]   Run with run_in_background; read the log afterwards and work out % per hour on battery.
set -u
until_t=${1:-02:00}; L=${2:-$HOME/Library/Logs/battery-log.txt}
end=$(date -j -f "%H:%M" "$until_t" +%s 2>/dev/null) || { echo "bad time $until_t"; exit 1; }
[ "$end" -le "$(date +%s)" ] && end=$(( end + 86400 ))
mkdir -p "$(dirname "$L")"
while [ "$(date +%s)" -lt "$end" ]; do
  b=$(pmset -g batt | awk -F'\t' 'NR==2{print $2}' | cut -d';' -f1,2)
  src=$(pmset -g batt | awk -F"'" 'NR==1{print $2}')
  top5=$(/usr/bin/top -l 2 -s 3 -o power -n 5 -stats power,command 2>/dev/null | tail -5 | awk '{c=$2; for(i=3;i<=NF;i++) c=c" "$i; printf "%s=%s, ", c, $1}')
  echo "$(date +%H:%M) | $b | $src | front=$(human front 2>/dev/null) | load=$(sysctl -n vm.loadavg | awk '{print $2}') | $top5" >> "$L"
  sleep 600
done
echo "$(date +%H:%M) done" >> "$L"
echo "log: $L"
