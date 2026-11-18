#!/usr/bin/env bash
# Fair power reading for one app: average Energy Impact of its processes, WindowServer and the graphics chip.
# usage: measure-app.sh <process-name-regex> [seconds=30] [--wait-front <AppName>]
#   --wait-front waits (up to 2 h) until the user brings that app to the front on their own; it never switches windows.
set -u
re=${1:?process name regex, e.g. "^Herdr$"}; secs=${2:-30}; front=""
[ "${3:-}" = "--wait-front" ] && front=${4:?app name for --wait-front}
if [ -n "$front" ]; then
  end=$((SECONDS+7200))
  until [ "$(human front 2>/dev/null)" = "$front" ]; do [ $SECONDS -ge $end ] && { echo "gave up: $front never came to the front"; exit 1; }; sleep 20; done
fi
samples=$(( secs / 5 + 2 ))
f0=$(human front 2>/dev/null)
/usr/bin/top -l "$samples" -s 5 -stats pid,power,command -o power -n 80 2>/dev/null | awk -v R="$re" '
  /^PID/ { s++; next }
  s>=2 { c=$3; for(i=4;i<=NF;i++) c=c" "$i; if (c ~ R) app+=$2; if (c=="WindowServer") ws+=$2 }
  END { n=(s>1)?s-1:1; printf "app power %.1f  WindowServer %.1f  (average of %d samples, first skipped)\n", app/n, ws/n, n }'
g=0; for i in 1 2 3 4 5; do v=$(ioreg -r -c IOAccelerator -d 1 2>/dev/null | /usr/bin/grep -o '"Device Utilization %"=[0-9]*' | head -1 | cut -d= -f2); g=$((g+${v:-0})); sleep 1; done
f1=$(human front 2>/dev/null)
echo "graphics chip busy $((g/5))%  front app: $f0 -> $f1"
command -v herdr-app >/dev/null && herdr-app ls 2>/dev/null | /usr/bin/grep -oE '"status": *"[a-z_]+"' | tr -d '"' | awk '{print $2}' | sort | uniq -c | awk 'BEGIN{printf "herdr agents:"} {printf " %s %s", $1, $2} END{print ""}'
[ "$f0" != "$f1" ] && echo "note: the front app changed during the reading, so it is not clean"
exit 0
