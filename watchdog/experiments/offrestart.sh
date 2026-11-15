#!/bin/bash
# wifi off, restart Upwork with watchdog during the outage, wifi on. Always restores wifi.
export PATH=$HOME/dotfiles/bin:$PATH; OUT=/private/tmp/claude-501/uwtest/offrestart.txt; : > $OUT
( sleep 400; networksetup -setairportpower en0 on ) & T=$!
trap 'kill $T 2>/dev/null; networksetup -setairportpower en0 on' EXIT
snap(){ echo "$(date +%T) $1 net=$(ping -c1 -t2 1.1.1.1 >/dev/null 2>&1 && echo up || echo DOWN) proc=$(pgrep -x Upwork|head -1) :: $(human see --app Upwork 2>/dev/null | awk -F'\t' '$4~/Time tracking|Connection|Start$|Stop$|Exit|Cancel|Sign|Log in|Email|offline|Offline|Try again|Retry|Continue/{printf "%s;",$4}')" >> $OUT; }
snap before; networksetup -setairportpower en0 off; echo "WIFI OFF $(date +%T)" >> $OUT
for i in 1 2 3; do sleep 5; snap off; done
echo "--- watchdog upwork-restart (offline)" >> $OUT; WD_VERBOSE=1 watchdog upwork-restart >> $OUT 2>&1
for i in 1 2 3 4; do sleep 5; snap off-after-restart; done
networksetup -setairportpower en0 on; echo "WIFI ON $(date +%T)" >> $OUT
for i in 1 2 3 4 5 6; do sleep 8; snap online; done; echo DONE >> $OUT
