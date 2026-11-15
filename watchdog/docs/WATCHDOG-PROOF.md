# Watchdog proof 2026-11-16 01:42:45

- PASS syntax: bash -n ok
- PASS daemon: launchd pid 36149, heartbeat 5s old
- PASS claude-detect: error texts BAD, normal text fine
- PASS claude-restart: fake terminal with API error triggers restart: claude restarting: API error on screen DRY: /tmp/wdself.4A2F/bin/hc run --bg ech
- PASS wifi-detect: 3 bad checks trigger the fix
- PASS wrong-network: warns when subnet differs
- PASS mouse: nudge ran, cursor 1000,333 -> 1000,333
- PASS upwork-offline-rule: flag set 70s with net up => restart
- PASS upwork-no-false-restart: flag clear => no action
- PASS crash-restart: killed 36149, launchd started 36655
- PASS single-instance: second loop refused: already running (36655)
- PASS upwork-stopped-recovery: was 'Time tracking off', daemon clicked Start, recording after 90s
- PASS wifi-real-restore: Wi-Fi forced off, daemon restored internet in 36s: 2026-11-16 01:43:50 wifi Wi-Fi power was off, turning on

Result: 13 pass, 0 fail

## Proven earlier (log evidence in UPWORK-STEP-LOG.md, not re-run here)
- Upwork restart with no internet: quit, Exit, reopen, Start, recording in 30s.

## Not testable in 5 minutes
- Real power cut, reboot and sleep recovery (needs the Mac restarted or slept).
- 24 hour soak.
