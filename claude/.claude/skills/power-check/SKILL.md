---
name: power-check
description: Check why the Mac is slow, hot or draining its battery, and what to fix, without disturbing the user. Use when the user asks to "check the system", "check power", "why is the battery draining", "what is using CPU or RAM", "is everything good now", "why is the wifi slow", or after a fix to measure whether it helped.
---

# Power check

Find what is costing battery, CPU and memory on Hassan's MacBook Pro (M1 Pro, 16 GB), measure it fairly, and report what to fix. The user keeps working while you check, so the check is read-only and never touches their windows unless they are away.

Scripts in this folder (all read-only unless named otherwise):

| Script | What it does |
| --- | --- |
| `snapshot.sh` | One 25 second snapshot: load, battery health and settings, sleep blockers, memory and swap, top energy users, per-app totals, graphics chip, known suspects |
| `measure-app.sh <regex> [secs] [--wait-front App]` | Fair reading for one app: its Energy Impact, WindowServer and the graphics chip, with Herdr agent states |
| `chrome-report.py` | Chrome load by process type, uptime, Energy and Memory Saver state, sites and enabled extensions per profile |
| `battery-log.sh [HH:MM] [file]` | Logs battery and top users every 10 minutes until a time; run in the background |
| `wait-away.sh [min] [hours]` | Exits once keyboard and mouse have been idle N minutes; gate for anything that needs the screen |

`reference.md` holds the baselines measured on this Mac, every fix already applied, and the pitfalls that cost time before. Read it before judging numbers.

## Ground rules

- Read-only first. Measure, then propose. Settings, extensions, plugins and system changes need the user's yes; the Claude settings file is guarded and needs explicit approval.
- Never switch, hide or close the user's windows while they are active. Do not quit Herdr. If a step needs the screen (Chrome's Task Manager, chrome://extensions, clicking in an app), start `wait-away.sh` with run_in_background and do it when it fires, then put the previous app back in front.
- Before heavy work, check `sysctl -n vm.loadavg`; above 20, say so first.
- `sudo` steps (pmset) cannot run from here: give the user the exact `! sudo ...` line to type.

## 1. Snapshot

Run `snapshot.sh`. Compare every line with the baselines in `reference.md`. Things that matter most:
- Load above the core count (8) for minutes, or a single process near or above 100% CPU.
- Swap above about 4 GB together with free memory under 20%: the Mac is paging now. High swap with plenty of free memory is left over from earlier and only a restart clears it.
- A `caffeinate` whose parent is pid 1 or that is hours old: an orphan keeping the Mac awake. Short `caffeinate -i -t 300` children of Claude sessions are normal.
- Battery sleep settings at 0 (never), Low Power Mode off on battery.
- Herdr spinners not frozen (any number above 0) or Claude reduce motion not True: a Herdr update or a settings reset undid a fix.
- Busy system daemons (contactsd, sharingd, mds_stores, duetexpertd, corespeechd, coreaudiod): name them and say what they do; most settle on their own.

## 2. Find the cause

Go only as deep as the snapshot points.

**An app's real cost.** Use `measure-app.sh` with the app in front. A hidden app reads near zero, so a reading only counts when the front app stayed the same (the script says so). To compare idle and working, read `herdr agents` in its output; to wait for the user to bring an app forward, pass `--wait-front`. Run two readings: one high reading right after a change is often a reload spike.

**Chrome.** Run `chrome-report.py`. Many enabled extensions with content scripts load into every page; tab processes using most of the CPU point at one runaway tab. To name the tab, wait until the user is away, then open Chrome's Task Manager from the menu (`human menu Window "Task Manager" --app "Google Chrome"`), sort by CPU, read the pid next to the top row, close only the Task Manager, and put the previous app back. Confirm with `ps -p <pid> -o pcpu=` a few times. Do not use Shift+Esc: web apps such as Teams take that shortcut.

**Herdr.** Animated spinners redraw the whole window about 30 times a second. Check the mods with the snapshot line; if they came back, see "Herdr spinners" in `reference.md`.

**Docker.** Count containers (`docker ps`). A full local Supabase stack is about 12 containers and around 15 Energy Impact on its own.

**Battery over hours.** Start `battery-log.sh` in the background (ask the user to unplug for a while), then report % per hour on battery and the usual top users.

**Wifi or internet slow.** First confirm which network: `system_profiler SPAirPortDataType` (a 10.x gateway or an open network is usually a phone hotspot). Then router and internet latency (`ping` the gateway and 1.1.1.1), loaded latency (`networkQuality`, run alone, never alongside other tests), and DNS (`scutil --dns`; a 127.0.0.1 resolver means a local DNS proxy such as NextDNS or ublockdns; compare `dig` through it with `dig @<router>`). Changing DNS is a system change: ask first.

## 3. Report

Lead with the answer: good or not, and the one thing that costs the most. Then a short checklist: the numbers that matter, each compared with its baseline or the previous reading, the cause in plain words, and the fixes ranked by gain, each marked "I can do it" or "needs you" (sudo, settings approval, screen time). Never call something fixed without a before and after reading.

## 4. Fixes that worked here

The catalogue with exact commands is in `reference.md`: battery sleep settings, orphan caffeinate, Herdr spinners, Claude reduce motion, Chrome extensions, a runaway web app tab (ad blocker off for that site), stale Claude installs and hooks, Docker and Supabase. Apply only what the user approved, then measure again with the same script.
