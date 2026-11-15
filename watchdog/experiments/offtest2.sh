#!/bin/bash
# usage: offtest2.sh OFF_SECONDS AFTER_SECONDS ; read only, restores wifi twice over
export PATH=$HOME/dotfiles/bin:$PATH
S=/private/tmp/claude-501/uwtest; OUT=$S/long-$(date +%H%M%S).tsv
LOG=~/Library/Application\ Support/Upwork/Upwork/Logs/upwork..$(date +%Y%m%d).log
( sleep $(( $1 + $2 + 120 )); networksetup -setairportpower en0 on ) &
trap 'networksetup -setairportpower en0 on' EXIT
sample(){ human focus Upwork >/dev/null 2>&1
 n=$(ping -c1 -t2 1.1.1.1 >/dev/null 2>&1 && echo net || echo NONET)
 t=$(human see --app Upwork 2>/dev/null | awk -F'\t' '$4!~/Learn|billing|Make sure|hours\.|Messages|alert|Minimize|Zoom|Close|Total hours|View|memo|working on|Full Stack|session|Latest|This week|Today|^[0-9]+ hours/{printf "%s;",$4}')
 l=$(tail -n 60 "$LOG" | grep -aE "ffline|rror|FAIL|Toggled|UPLOAD_FINISHED|httpStatus" | tail -2 | tr -s ' \t\n' ' ' | cut -c1-120)
 echo -e "$(date +%T)\t$1\t$n\t$t\t$l" >> $OUT; }
for i in 1 2 3; do sample before; sleep 4; done
networksetup -setairportpower en0 off; echo "WIFI OFF $(date +%T)" >> $OUT
e=$((SECONDS+$1)); while [ $SECONDS -lt $e ]; do sample off; sleep 3; done
networksetup -setairportpower en0 on; echo "WIFI ON $(date +%T)" >> $OUT
e=$((SECONDS+$2)); while [ $SECONDS -lt $e ]; do sample after; sleep 3; done
echo DONE >> $OUT
