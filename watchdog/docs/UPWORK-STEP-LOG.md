# Upwork study step log (2026-11-16)

## Steps done, in order
1. Read the handoff. Found `human` is not on PATH; use ~/dotfiles/bin/human.
2. Read-only: `human see --app Upwork` reads the window as text. Recording shows "Time tracking on" and "Stop".
3. Read Upwork logs in ~/Library/Application Support/Upwork/Upwork/Logs. Found TRACKER_STEP and TRACKER_UPLOAD_FINISHED lines.
4. Hassan allowed clicking controls for learning (no hard rule). Nothing clicked yet.
5. 00:12: `networksetup -getairportnetwork en0` said "not associated" while ping to 8.8.8.8 worked. That command is wrong on this Mac, do not use it for the watchdog.
6. 00:13: ran a Wi-Fi off test (script /private/tmp/claude-501/uwtest/offtest.sh) for about 90 seconds. It always turns Wi-Fi back on.

## Findings so far
- The offtest sampler took 5 to 8 seconds per sample, so it is slow.
- The screen text "0:49 hrs" and "11 mins ago" did NOT change for 2+ minutes, even before Wi-Fi went off. With Upwork in the background the window text looks frozen. To check with Upwork in front.
- During the Wi-Fi off test the screen text showed no offline message at all. To check if it needs a longer outage.
- Ping showed NONET for about 70 seconds, then net again before my script turned Wi-Fi on (the Mac reconnected by itself). To check why.
- Mistake: I did not warn that Wi-Fi off also cuts my own Claude connection. A tool result was lost during it.

## Rules I now follow
- Before anything that can cut the network, say so and run it as a detached script that restores itself.
- Write each step here as I do it.

7. 00:2x: focused Upwork with human focus, read 3 times 20s apart (see next line for result).
   Result: with Upwork in FRONT the text updates (today 10:50, "8 mins ago"). In the background it stayed frozen. So the watchdog must bring Upwork forward (human focus Upwork) before reading, then return focus.
   Note: session counter shows '1:04 hr' (singular hr) after one hour, so match 'hrs?$'. Offtest finished: DONE.
8. 00:17: user allowed clicks. Clicking Stop once to capture the stopped screen, then restarting at once.
   Result: 'human click Stop' failed (could not see). Window was scrolled down so Stop was hidden (header collapsed, Stop 17px tall). Need to scroll up first.
9. 00:18:05: clicked Stop once (see next lines for the stopped screen).
   Result: click by name failed ('could not see Stop'); retry by coordinates (864,149 is the button centre from human see).
   Result: Stop shows a confirm sheet: "Time tracking in progress / Would you like to stop tracking time?" with buttons "Yes, stop tracking" and "Cancel". The sheet itself is a state to detect (a stuck sheet means not recording decision pending).
10. 00:18: clicking "Yes, stop tracking" (user allowed), then reading the stopped screen.
   Result (STOPPED screen): app goes to the contract list ("All contracts", search box, refresh button). Contract row shows "Time last tracked <date>" and "This week's hours". No "Time tracking on", no Stop button. Time on stop: this week 27:10 -> 27:20 hrs.
11. 00:18: clicking the contract row to open it and find Start.
   Result (contract page, stopped): "Time tracking off", session "0:00 hrs", green button "Start" (no Stop). Today total moved 10:50 -> 11:00.
12. 00:19: clicked Start at 863,376 to resume recording. Gap with no tracking: about 1 minute.
   Result: Start works, 'Time tracking on' and Stop are back at 00:18:49. Log lines 'Tracker Toggled { status: stopping|started }' mark each click.
13. 00:20:46: wrote offtest2.sh (focuses Upwork each sample, backup wifi-on timer). Dry run with 0s outage next.
14. 00:21:17: dry run OK (even a 1s Wi-Fi off wrote a trackingOffline close line in the log). Starting real test: 180s off, 120s after. Output: /private/tmp/claude-501/uwtest/long-*.tsv
   Result of 180s test (00:21:33 to 00:24:34), verified in /private/tmp/claude-501/uwtest/long-*.tsv and the Upwork log:
   - OFFLINE screen: "Time tracking on" and Stop stay, session counter KEEPS counting, and a new text "Connection lost" appears about 4s after the internet drops. It disappears when the internet returns.
   - OFFLINE log: `show { type: 'trackingOffline' }` within about 1s of the drop (a small window at top right, top 49 left 1346). `onClose { type: 'trackingOffline' }` when back online. Even a 1s Wi-Fi off wrote both lines.
   - So Upwork keeps recording locally while offline; "Connection lost" is a warning, not a stop.
   - Surprise: ping came back at 00:23:29, about 2 min into the 3 min "off". Something re-enabled the connection (macOS or another tool). To check what.
15. Mistakes to avoid: none this time; Wi-Fi was on at the end.
16. 00:29:18: investigating why net returned early. Suspect: dry-run offtest2.sh left its backup timer (sleep 125 then wifi on) running into the real test. Test A: clean 75s off with no timers, polling power+ping each second.
   Test A result: power stayed Off and ping failed for the full 156s (00:29:20 to 00:31:56). Nothing turned Wi-Fi back on by itself.
17. 00:32:48: Test B: leave a backup timer (sleep 30, wifi on) behind on purpose, script ends early, see if power flips at timer time.
   Test B result: a leftover backup timer (sleep 30 then wifi on) flipped power Off to On at exactly +30s (00:32:52 off, 00:33:22 on) after its script had exited.
   CAUSE OF EARLY RECONNECT (proven): the dry-run (started 00:20:46, backup timer 125s) left its timer behind. macOS log shows one `networksetup` run at 00:22:52.158, matching 00:20:46 + 125s. No other networksetup call between 00:21:41 and 00:24:40 in that window. Ping only recovered about 35s later (rejoin lag, to check).
   Fix: the script must kill its backup timer on normal exit.
   OFFLINE MINUTES, first evidence: Upwork log TRACKER_UPLOAD_FINISHED minutesWorkedToday 650 (00:08), 660 (00:18, on Stop), 670 (00:28:10). The 660 to 670 block covers the outage (00:21:33 to about 00:23:27) and credited the full 10 minutes. Screen "Today" 11:10 hrs = 670, matches the log.
   Limit: that upload happened while online. An upload due DURING an outage is not tested yet. Next test: 13 minute outage across an upload boundary (about 00:38).
   Note: `log` in zsh is a shell builtin, use /usr/bin/log.
18. 00:35:11: starting 13 min outage test (long3.sh 780 420) across the next upload boundary.
   13 min outage result (00:35:22 off, 00:48:31 on, verified in L3 tsv and the Upwork log):
   - Screen: "Connection lost" the whole time, timer kept counting (0:16 to 0:32 hrs).
   - Uploads (minutesWorkedToday): 670 at 00:28:10, then NONE during the outage, then 680 at 00:49:06 after reconnect.
   - At 00:55 session counter 0:36 hrs but Today showed 11:20 (680). About 16 min not credited yet. Not proven lost: a later upload (due about 00:58) was not checked. Test stopped by Hassan.
19. 00:58: Hassan stopped the test. Wi-Fi on, timer recording, nothing committed.
20. 01:05:51: Hassan: missed offline minutes are NOT credited (accepted, no more checking). Build watchdog in ~/dotfiles/bin, incl. close and reopen Upwork when the connection is out. No QA resume.
21. 01:05:58: testing Upwork quit (osascript quit) while tracking, to learn what it does.
   Result: quit while tracking shows a sheet 'Would you like to exit?' with buttons Exit and Cancel (button centres from human see). Process stays until Exit is clicked.
   Result: Exit click quits cleanly in about 2s and logs Tracker Toggled stopping. 'open -a Upwork' returns in about 10s straight to the contract page with 'Time tracking off' and a Start button (stays logged in, no login screen). Clicking Start (centre coords from human see) restarts recording at 01:07:31.
   Note: in zsh pass x and y as two words (human click 1150 370); a variable holding 'x y' is not split. Window position changes after reopen (Start was at 1150,370).
22. 01:08:52: wrote ~/dotfiles/bin/watchdog (parts: wifi awake upwork claude, WD_DRY for dry runs). Testing each part next.
   Found: Mac was on 192.168.100.x at 00:12 to 00:51 and is on 192.168.0.x at 01:09:10. SSID is hidden by macOS, so the subnet is the only clue to which network we are on.
   Wi-Fi fix test (real): forced 3 bad checks, script ran `networksetup -setairportnetwork en0 "<first floor SSID>"` and it joined (ip 192.168.0.100). An earlier manual try failed with error -3900 (transient). So F.B = 192.168.0.x; 192.168.100.x seen 00:12 to 00:51 was another network, probably after my power cycles. Power cycle can land on the wrong network, so the script tries the direct rejoin first.
23. 01:11:31: test watchdog upwork-restart (real).
25. 01:14:33: test: Upwork quit, reopen, Start while Wi-Fi is OFF (offrestart.sh, restores itself). Output /private/tmp/claude-501/uwtest/offrestart.txt
26. 01:18:28: test: stop timer by hand, watchdog upwork part should notice no ticks and click Start.
   Offline restart test (offrestart.sh): with Wi-Fi OFF, `watchdog upwork-restart` quit Upwork (Exit click), reopened, clicked Start, recording confirmed in about 30s. Screen then shows "Connection lost". Wi-Fi on: log offline flag cleared 2s later (01:16:01) and an upload finished at 01:16:04. The screen text stayed "Connection lost" because Upwork was in the background (screen text only updates in front), so the LOG is the reliable offline signal.
   Stopped-timer test: stopped by hand 01:19:54, watchdog saw no ticks at 52s, clicked Start, recording confirmed 01:21:12 (about 72s untracked).
   Stop button sometimes stops at once with no confirm sheet, sometimes asks. The watchdog handles both because it only looks for Start.
27. 01:22:52: watchdog under launchd logged 'human cannot read Upwork' (no Accessibility for launchd child). Built Human.app via ~/dotfiles/human-input/make-app.sh so it can hold its own grant.
28. 01:25:04: stopped timer by hand, waiting for the launchd watchdog to restart it
29. 01:26:36: test: Wi-Fi forced off, launchd watchdog must restore it itself (backup restores at +150s).
30. 01:30:01: BUG found: rejoin cmd returns ok when Wi-Fi power is off, so watchdog never turned it on (only my backup did). Fixed wifi_cycle to turn power on first and verify rejoin by ping. Retesting.
   Result: after the fix, launchd watchdog turned Wi-Fi on by itself: off 01:30:01, internet back 01:30:35 (log: "Wi-Fi power was off, turning on"). Backup timer did not fire.
