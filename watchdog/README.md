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
- Claude session: off until CLAUDE_TERM (an hc --name, so it survives restarts) and CLAUDE_RESTART_CMD are set. Restarts after 60 s of API error text, 3 min frozen while busy, or the terminal gone. Recreated with the same name, folder and Herdr tab. Waits for internet, 90 s grace after a restart, max 6 an hour then 1 per 15 min.
- Power: logs mains lost and back, and every 10% of battery. At 5% battery it stops Upwork cleanly (saves the current time block) and does not reopen it until mains is back.
- Upwork window: before reading it un-minimizes, un-hides, brings it to front and scrolls to the top, so a moved, scrolled, minimized, hidden or closed window still works (tested, also with no internet).
- Pause everything: touch ~/.cache/watchdog/paused (delete it to resume). Turn off only the Claude watch: touch ~/.cache/watchdog/claude_off.
- Power cut or sleep: launchd restarts it and the log shows the gap.

## Limits
- Each recovery loses 30 to 80 s of tracked time. Offline minutes are not credited.
- FileVault is on with no auto-login: after the battery dies the Mac waits at the password screen and nothing runs until you log in.
- Lid close on battery still sleeps the Mac (caffeinate cannot stop that).
- Real reboot recovery is untested.
