# Power check reference

Measured on Hassan's MacBook Pro (M1 Pro, 8 cores, 16 GB, battery 262 cycles, 90% capacity) on 2026-11-18. "Power" is macOS Energy Impact from `top -o power`; "GPU" is IOAccelerator Device Utilization.

## Baselines

| Thing | Bad (before fixes) | Good (after) |
| --- | --- | --- |
| Battery from full | about 1 hour | about 5.5 to 6 hours |
| Load (8 cores) | 9 to 57 | 3 to 7 |
| Swap | 10.9 GB | under 6 GB, cleared by a restart |
| Herdr in front, agents idle | 22 to 26, GPU about 30% | 1 to 2.4, GPU 3 to 7% |
| Herdr in front, agents working | 21 | 4.5, GPU 12% |
| Herdr hidden | 0.7 to 1.5 | same |
| cmux in front, idle | 2 to 3, GPU 1% | same |
| Chrome total CPU | about 220% | 5 to 50% |
| Chrome extension processes | 15, 33% CPU, 840 MB | 2, 0.1%, 114 MB |
| One Slack tab | 80 to 150% CPU | about 7% |
| Supabase in OrbStack (12 containers) | about 14 to 17 power, 1.5 GB | `supabase stop` when not on Passenger |
| Bluetooth daemon | 26 to 31 power when on with devices | under 2% when off |

## Fixes applied (check they still hold)

- **Battery sleep and Low Power Mode**: `sudo pmset -b displaysleep 5 sleep 15 lowpowermode 1` (battery only; the user runs it with `!`). Check with `pmset -g custom`.
- **Orphan caffeinate**: a `caffeinate -dimsu` with parent pid 1 ran for days and kept the Mac and screen awake. Fix: `kill <pid>` after checking `ps -o ppid,etime,args -p <pid>`.
- **Herdr spinners**: in `~/.config/herdr-app/mods`, `.spin(900)` was removed from `agents`, `pane`, `tabs` and `picker` (Herdr's own files, not in dotfiles, so a Herdr update can bring them back), and `.loop("opacity", ...)` from `spaces-tree` (in dotfiles). Re-apply: `sed -i '' 's/\.text_color(t\.working)\.spin(900)/.text_color(t.working)/'` on those four files, then `herdr-app check ~/.config/herdr-app/mods/<mod>` for each. Herdr reloads mods without a restart.
- **Claude Code reduce motion**: `"prefersReducedMotion": true` in `claude/.claude/settings.json` (guarded file, needs approval). Cut Herdr from 21 to 4.5 while agents work.
- **Chrome extensions**: 16 turned off in the Default profile (wallets, VPNs, Auto Refresh, Grammarly, Readwise, WhatRuns, NoteGPT, Hunter, Loom, Capsule Hub, React and Redux DevTools, Fake Filler, Instant Data Scraper) and Browsec in the Teams profile. Way that works: when the user is away, `open -na "Google Chrome" --args --profile-directory=Default` opens a window in the right profile; Cmd+L, type `chrome://extensions/?id=<id>`, Enter; the On switch sits at the same spot on every detail page. Confirm in `Secure Preferences` (`disable_reasons` set), close the window afterwards.
- **Runaway web app tab**: a Slack tab used a full core because the ad blocker kept re-checking Slack's live page. Fix: ad blocker off for that site only.
- **Claude Code clutter**: old Homebrew `claude-code` cask removed (the native one in `~/.local/bin` is used), dead graphify hook and duplicate reply-style hook removed, stale plugin and marketplace entries removed, duplicate superpowers plugin removed.
- **cmux**: kept as a low-power fallback with a Herdr-look sidebar (`cmux/.config/cmux/sidebars/herdr.js`).

## Still open (user's choice)

- Supabase running all the time; Upwork open; several Claude sessions; Chrome rarely restarted (5 days); swap needs a restart.
- DNS: NextDNS and ublockdns proxy every lookup on 127.0.0.1 and send Google to US servers (138 to 225 ms against about 22 ms through the router). The user said not to change it yet.

## Pitfalls that cost time

- In zsh, `$var` holding several file names is one argument; use an array or a file list.
- `/usr/bin/grep` has no `-P`; with `2>/dev/null` a check silently passes. Use Python for Unicode checks such as long dashes.
- `top` and `ls` are aliased (btop, eza) in interactive shells; call `/usr/bin/top` and `/bin/ls`.
- Run network and power tests one at a time; parallel tests skew each other.
- `osascript ... quit` hangs when the app shows a confirm dialog (cmux confirms quit); use `pkill -x <app>` for an app you opened yourself.
- Shift+Esc in Chrome goes to the page first: Teams opened "mark all as read?". Use the Window menu.
- `open -a "Google Chrome" chrome://...` lands in whichever profile window was last active, or a blank tab.
- `screencapture -l <windowid>` captures a window behind others; screen coordinates for `human click` are in points with the window origin (often y=39 under the menu bar), screenshots are 2x.
- Herdr's own "working" status covers this session too, so a reading taken while you run commands is a "working" reading.
- A background `pkill` of a waiting script reports the task as failed (exit 144); that is expected.
