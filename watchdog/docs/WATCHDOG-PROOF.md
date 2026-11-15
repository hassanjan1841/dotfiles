# Watchdog proof 2026-11-16 02:03:49

- PASS syntax: bash -n ok
- PASS daemon: launchd pid 52153, heartbeat 2s old
- PASS claude-detect: error texts BAD, normal text fine
- PASS claude-error-new: none (claude error text on screen, watching)
- PASS claude-error-60s: restart (claude restarting qa: API error on screen 60s claude started again: {")
- PASS claude-no-internet: none (claude API error on screen 60s, no internet, restart waits for it)
- PASS claude-frozen-busy: restart (claude restarting qa: busy but screen frozen 180s claude started again)
- PASS claude-idle-quiet: none ()
- PASS claude-missing: restart (claude restarting qa: terminal missing claude started again: {"address)
- PASS claude-same-place: recreated with same name, folder and Herdr tab
- PASS claude-rate-cap: none ()
- PASS claude-grace: none ()
- PASS claude-off-switch: none ()
- PASS power-lowbatt: battery 4% => logged and Upwork stopped cleanly
- PASS power-once: only one clean stop
- PASS power-no-reopen: Upwork not reopened while on low battery
- PASS power-mains-back: mains back => Upwork allowed again
- PASS log-cap: 5.2MB log trimmed to 205031 bytes
- PASS wifi-detect: 3 bad checks trigger the fix
- PASS wrong-network: warns when subnet differs
- PASS mouse: nudge ran, cursor 901,489 -> 901,489
- PASS upwork-offline-rule: flag set 70s with net up => restart
- PASS upwork-no-false-restart: flag clear => no action
- PASS crash-restart: killed 52153, launchd started 53368
- PASS single-instance: second loop refused: already running (53368)
- PASS upwork-stopped-recovery: was 'Time tracking off', daemon clicked Start, recording after 77s
- PASS wifi-real-restore: Wi-Fi forced off, daemon restored internet in 33s: 2026-11-16 02:05:01 wifi Wi-Fi power was off, turning on

Result: 27 pass, 0 fail

## Proven earlier (log evidence in UPWORK-STEP-LOG.md, not re-run here)
- Upwork restart with no internet: quit, Exit, reopen, Start, recording in 30s.

## Not testable in 5 minutes
- Real power cut, reboot and sleep recovery (needs the Mac restarted or slept).
- 24 hour soak.
