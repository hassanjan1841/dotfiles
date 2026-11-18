#!/usr/bin/env bash
# Read-only snapshot of battery, power settings, load, memory and the biggest power users.
# Takes about 30 seconds. Touches no window and changes nothing.
set -u
export LC_ALL=C
TOP=/usr/bin/top            # `top` may be aliased (btop) in interactive shells
GREP=/usr/bin/grep

h(){ printf '\n== %s\n' "$1"; }
gpu(){ local g=0 v i; for i in 1 2 3 4 5; do v=$(ioreg -r -c IOAccelerator -d 1 2>/dev/null | $GREP -o '"Device Utilization %"=[0-9]*' | head -1 | cut -d= -f2); g=$((g+${v:-0})); sleep 1; done; echo $((g/5)); }
in_secs(){ perl -e 'alarm shift; exec @ARGV' "$@"; }

h "Time and load"
echo "time: $(date '+%a %d %b %H:%M')  front app: $(human front 2>/dev/null || echo unknown)"
cores=$(sysctl -n hw.ncpu); read -r l1 l5 l15 < <(sysctl -n vm.loadavg | tr -d '{}')
echo "load: $l1 / $l5 / $l15 (1m/5m/15m) on $cores cores"
echo "uptime: $(uptime | sed -E 's/.*up ([^,]*),.*/\1/')"

h "Battery"
pmset -g batt | sed -n '1,2p' | sed 's/^ *//'
system_profiler SPPowerDataType 2>/dev/null | $GREP -E 'Cycle Count|Condition|Maximum Capacity' | sed 's/^ */  /'

h "Power settings (battery / charger)"
pmset -g custom 2>/dev/null | awk '/Battery Power:/{m="battery"} /AC Power:/{m="charger"} $1~/^(sleep|displaysleep|lowpowermode|powernap)$/{printf "  %-8s %-13s %s\n", m, $1, $2}'
pmset -g therm 2>/dev/null | $GREP -iE 'CPU_Speed_Limit|warning level' | sed 's/^/  /'

h "Sleep blockers"
pmset -g assertions 2>/dev/null | $GREP -E 'PreventUserIdle(System|Display)Sleep|PreventSystemSleep|NoIdleSleep' | $GREP -E 'pid [0-9]+' | sed -E 's/^ *pid ([0-9]+)\(([^)]+)\): \[[^]]*\] ([0-9:]+) [A-Za-z]+ named: "([^"]*)".*/  \2 (pid \1) for \3: \4/' | sort -u | head -12
for p in $(pgrep -x caffeinate); do
  printf '  caffeinate pid %s parent %s age %s: %s\n' "$p" "$(ps -o ppid= -p "$p" | tr -d ' ')" "$(ps -o etime= -p "$p" | tr -d ' ')" "$(ps -o args= -p "$p")"
done

h "Memory"
total=$(( $(sysctl -n hw.memsize) / 1073741824 ))
echo "RAM: ${total} GB, $(memory_pressure 2>/dev/null | $GREP 'free percentage' | sed 's/.*: //') free"
sysctl vm.swapusage | awk '{print "swap: "$7" used of "$4}'

h "Top energy users (15 s average, Energy Impact)"
$TOP -l 4 -s 4 -o power -n 14 -stats pid,cpu,power,command 2>/dev/null | awk '/^PID/{s++; next} s==4' | awk '{c=$4; for(i=5;i<=NF;i++) c=c" "$i; printf "  power %5s  cpu %5s  %-24s pid %s\n", $3, $2, c, $1}' | head -14
echo "  graphics chip busy: $(gpu)%"

h "By app (CPU % of one core, memory)"
ps -Ao pcpu,rss,comm | awk 'NR>1{
  n=split($0,a,"/"); c=a[n]; g="other"
  if(c~/chrome-headless|Chrome for Testing/) g="test browsers"
  else if(c~/Google Chrome/) g="Chrome"
  else if(c~/^ *[0-9.]+ +[0-9]+ claude$/ || c~/^claude$|^2\.[0-9]+\.[0-9]+$/) g="Claude CLI"
  else if(c~/OrbStack|com\.docker|vmnet|qemu/) g="OrbStack/Docker"
  else if(c~/Herdr/) g="Herdr"; else if(c~/cmux/) g="cmux"
  else if(c~/Slack/) g="Slack app"; else if(c~/Teams|MSTeams/) g="Teams"
  else if(c~/WhatsApp/) g="WhatsApp"; else if(c~/Upwork/) g="Upwork"
  else if(c~/WindowServer/) g="WindowServer"
  cpu[g]+=$1; ram[g]+=$2
} END{for(k in cpu) printf "  cpu %6.1f%%  ram %5.1f GB  %s\n", cpu[k], ram[k]/1048576, k}' | sort -k2 -nr

echo "  busiest single processes:"
ps -Ao pcpu,pid,comm -r | awk 'NR>1 && NR<=9{n=split($0,a,"/"); c=a[n]; sub(/^ *[0-9.]+ +[0-9]+ /,"",c); printf "    %5s%%  %-7s %s\n", $1, $2, c}'

h "Known suspects"
echo "  Claude sessions: $(pgrep -x claude | wc -l | tr -d ' ')"
echo "  docker containers: $(in_secs 8 docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
echo "  test browsers: $(pgrep -f 'Chrome for Testing|chrome-headless-shell' | wc -l | tr -d ' ') processes"
cpid=$(pgrep -x 'Google Chrome' | head -1); [ -n "$cpid" ] && echo "  Chrome running for: $(ps -o etime= -p "$cpid" | tr -d ' ')"
echo "  Bluetooth: $(system_profiler SPBluetoothDataType 2>/dev/null | $GREP -m1 'State:' | sed 's/.*State: //'), bluetoothd cpu $(ps -Ao pcpu,comm | awk '/bluetoothd$/{print $1; exit}')%"
for proc in mds_stores duetexpertd mdworker_shared; do c=$(ps -Ao pcpu,comm | awk -v p="$proc" '$2~p{s+=$1} END{print s+0}'); [ "${c%.*}" -ge 20 ] 2>/dev/null && echo "  $proc busy: ${c}% cpu"; done
mods="$HOME/.config/herdr-app/mods"
if [ -d "$mods" ]; then
  spins=$(cat "$mods"/{agents,pane,tabs,picker}/main.js 2>/dev/null | $GREP -c 'spin(900)')
  loops=$(cat "$mods"/spaces-tree/main.js 2>/dev/null | $GREP -c 'loop("opacity"')
  echo "  Herdr animated spinners in mods: $spins spin, $loops pulse (0 and 0 = frozen)"
fi
rm_=$(python3 -I -c "import json,os;print(json.load(open(os.path.expanduser('~/.claude/settings.json'))).get('prefersReducedMotion',False))" 2>/dev/null)
echo "  Claude Code reduce motion: ${rm_:-unknown}"
echo
echo "done"
