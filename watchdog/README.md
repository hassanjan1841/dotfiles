# watchdog

Offline keep-alive for this Mac. Plain shell, no internet, no AI. Run by launchd.

## Files
- bin/watchdog: the loop (parts: wifi, awake, upwork, claude)
- bin/watchdog-selftest: proves everything in about 2 minutes (`watchdog-selftest out.md`)
- watchdog/com.hassan.watchdog.plist: the launchd job (copy to ~/Library/LaunchAgents)
- watchdog/watchdog.conf.example: copy to ~/.config/watchdog/watchdog.conf
- watchdog/docs: findings, step log, last proof run, original handoff
- watchdog/experiments: the throwaway outage test scripts used to learn Upwork's behaviour

## Install
1. ~/dotfiles/human-input/make-app.sh (builds Human.app, grant it Accessibility once)
2. cp watchdog/com.hassan.watchdog.plist ~/Library/LaunchAgents/
3. cp watchdog/watchdog.conf.example ~/.config/watchdog/watchdog.conf
4. launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.hassan.watchdog.plist

Stop: launchctl bootout gui/$(id -u)/com.hassan.watchdog. Log: ~/Library/Logs/watchdog.log.

## What it does
- Wi-Fi: bad = dead, 2 of 5 pings lost, or over 400 ms. After 3 bad checks: power on if off, rejoin the first floor network, else power cycle.
- Awake: keeps caffeinate -dimsu running, 2 pixel mouse nudge every 90 s.
- Upwork: state comes from its log (TRACKER_STEP ticks), not the screen. No ticks for 45 s: click Start, restart only if that fails. "Connection lost" flag 60 s after internet returns, app missing or frozen: quit, Exit, reopen, Start. Focus returns to your app.
- Claude session: off until CLAUDE_TERM and CLAUDE_RESTART_CMD are set in the conf.
- Power cut or sleep: launchd restarts it and the log shows the gap.

## Limits
- Each recovery loses 30 to 80 s of tracked time. Offline minutes are not credited.
- Real power cut and reboot recovery are untested.
