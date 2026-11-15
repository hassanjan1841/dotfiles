# Upwork findings (read only study, 2026-11-15)

## Action list
1. Hassan: decide if the watchdog may ever restart the timer (not decided, nothing was clicked).
2. Hassan: say when I may test the broken states (Wi-Fi off, 1 minute). Not done yet.
3. Then build the watchdog on the two signals below (screen state plus log upload line).

## Recording state (seen on screen, 3 reads in a row identical)
- The app is Upwork 5.8.0 (Electron), window title "Time Tracker", about 375x800.
- Recording shows: "Time tracking on", a counting "Current session" value, and a red "Stop" button.
- Total hours tracked panel shows Today, This week, and "Latest screenshot, N mins ago".
- A yellow billing banner can sit over the lower part. It is not an error.
- Not seen yet: paused, stopped, offline, error. Marked to check.

## How to read it
- `human see --app Upwork` works (accessibility tree), no OCR needed. Verified 3 times.
- `human state --app Upwork` says "no usable tree", do not use it.
- Look for AXStaticText "Time tracking on" and AXButton "Stop". Stopped state text: to check.
- Session counter is AXStaticText like "0:22 hrs". Two reads a minute apart must differ: to check.
- `human see` works with Herdr in front, but the Upwork window must be on screen: to check when hidden.
- Menu bar has an Upwork icon. Its state when offline: to check.

## Logs (read only, nothing changed)
- Folder: ~/Library/Application Support/Upwork/Upwork/Logs
- Daily file `upwork..YYYYMMDD.log` (about 10MB), updated every few seconds while open.
- `TRACKER_STEP` lines come every few seconds while recording. Last one was seconds old when checked.
- `TRACKER_UPLOAD_FINISHED` with `"status": "S_OK"` and `"httpStatusCode": 200` is a proven upload of time.
- Today 133 uploads were S_OK, none failed. Gaps between uploads: about 3 to 6 minutes.
- That line also has `minutesWorkedToday`, a safe number to compare with the screen.
- `LOAD_FAIL` ("Failed to fetch") and `httpStatusCode` 700 appear on days with network drops (Nov 6, 8, 14).
- A `trackingOffline` window type exists in the log (Nov 8). What it looks like on screen: to check.
- `"offline": true/false` is an app property in the log. Exact meaning: to check.
- Files with sync queue state (UserData IndexedDB, Local Storage): not opened, to check.

## Safe watchdog signals (proposal)
- Recording OK: "Time tracking on" on screen AND newest `TRACKER_STEP` under 30 seconds old AND newest `TRACKER_UPLOAD_FINISHED` S_OK under 15 minutes old.
- Danger: no new `TRACKER_STEP`, or uploads missing for 15 minutes, or `trackingOffline` shown.
- Thresholds are guesses, to check with a real Wi-Fi off test.

## Not done
- No Start, Stop, Pause or setting touched. No private data kept; screenshots deleted.

## Added 2026-11-16 (verified, see UPWORK-STEP-LOG.md)
- Screen states: recording = "Time tracking on" + Stop. Offline = same plus "Connection lost" (counter keeps counting). Stopped = contract list, then "Time tracking off" + Start.
- Stop asks "Would you like to stop tracking time?" (Yes, stop tracking / Cancel).
- Log: `show { type: 'trackingOffline' }` on drop, `onClose { type: 'trackingOffline' }` on recovery. `Tracker Toggled { status: ... }` on Stop and Start clicks.
- Upwork must be in front for the screen text to update. Clicks need coordinates from `human see`, not names. Scroll up first if the window is scrolled.
- To check: longer outage (10 min) upload catch-up, and whether offline minutes are credited.
- 13 min outage: uploads stop while offline, one upload came after reconnect, and about 16 of 36 session minutes were not credited at the last check (00:55). To check: whether a later upload catches up.
- Early reconnect in the 3 min test was my own leftover backup timer, proven by a macOS log entry and a repeat test.

## Watchdog (built 2026-11-16), all tested live
- Script: ~/dotfiles/bin/watchdog. Job: ~/Library/LaunchAgents/com.hassan.watchdog.plist (RunAtLoad, KeepAlive). Log: ~/Library/Logs/watchdog.log. Config: ~/.config/watchdog/watchdog.conf. Stop: launchctl bootout gui/$(id -u)/com.hassan.watchdog.
- Wi-Fi: bad = dead, or 2 of 5 pings lost, or average over 400 ms. After 3 bad checks: turn power on if off, else rejoin F.B, else power cycle. Tested: Wi-Fi off, back in 34s.
- Awake: keeps caffeinate -dimsu running, 2 pixel mouse nudge every 90s. Nudge tested.
- Upwork recorded state comes from the log (TRACKER_STEP ticks), not the screen (screen text freezes when Upwork is in the background).
- No ticks for 45s: click Start first (tested, about 80s untracked), restart only if that fails.
- Offline log flag still set 60s after internet returns: quit, click Exit, reopen, click Start. Restart works with no internet (tested, 30s).
- App missing: open it and click Start. Focus returns to the app Hassan was in.
- After power loss or sleep: launchd restarts it and the log shows "watchdog was not running for N min". Not tested with a real power cut.
- Claude session watch: written, off by default (CLAUDE_TERM and CLAUDE_RESTART_CMD empty), because QA is paused and no leader session exists. Detection tested on sample text only.
- Missed offline minutes are treated as not credited (Hassan's call).
