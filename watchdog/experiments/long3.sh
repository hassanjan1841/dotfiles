#!/bin/bash
# usage: long3.sh OFF_S AFTER_S ; read only; restores wifi; kills its own backup timer on normal exit
export PATH=$HOME/dotfiles/bin:$PATH
S=/private/tmp/claude-501/uwtest; OUT=$S/L3-$(date +%H%M%S).tsv
LOG=~/Library/Application\ Support/Upwork/Upwork/Logs/upwork..$(date +%Y%m%d).log
( sleep $(( $1 + $2 + 200 )); networksetup -setairportpower en0 on ) & T=$!
trap 'kill $T 2>/dev/null; networksetup -setairportpower en0 on' EXIT
up(){ awk '/^\[2026-11-16T/{ts=substr($1,13,8)} /"type": "TRACKER_UPLOAD_(STARTED|FINISHED)"/{ty=substr($2,16,3);w=1} w&&/"httpStatusCode"/{h=$2} w&&/"minutesWorkedToday"/{r=ts" "ty" "h" "$2;w=0} END{print r}' "$LOG" | tr -d '",'; }
sample(){ human focus Upwork >/dev/null 2>&1
 n=$(ping -c1 -t2 1.1.1.1 >/dev/null 2>&1 && echo net || echo NONET)
 t=$(human see --app Upwork 2>/dev/null | awk -F'\t' '$4~/Time tracking|Connection|hrs?$|ago$/{printf "%s;",$4}')
 echo -e "$(date +%T)\t$1\t$n\t$t\t$(up)" >> $OUT; }
for i in 1 2; do sample before; sleep 4; done
networksetup -setairportpower en0 off; echo "WIFI OFF $(date +%T)" >> $OUT
e=$((SECONDS+$1)); while [ $SECONDS -lt $e ]; do sample off; sleep 8; done
networksetup -setairportpower en0 on; echo "WIFI ON $(date +%T)" >> $OUT
e=$((SECONDS+$2)); while [ $SECONDS -lt $e ]; do sample after; sleep 8; done
echo DONE >> $OUT
