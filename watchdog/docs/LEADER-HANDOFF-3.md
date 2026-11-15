# Leader 3 handoff (written 23:34 PKT, 15-Nov)

Hassan (the user) is working from the first floor. Reply to him in SHORT checklists, outcome first, plain words, no long dashes. He may be away from the Mac. No alerts or notifications: he may be offline, so notifying is pointless.

## What Hassan wants (the big goal)
A complete OFFLINE watchdog on this Mac that keeps his work safe when internet or power drops. It must work with no internet and no AI calls (plain shell script plus the human CLI, run by launchd or a loop). It does these, fixing things by itself, quietly logging to a file, never alerting:
1. Wi-Fi: test the real connection every few seconds. If dead or weak, move the Mac back to the good first-floor network the first floor network (the SaNi-5G and SaNi.NeT.736 networks are the weak ground-floor ones), renew the connection if needed.
2. Keep the Mac awake: caffeinate running, plus a harmless mouse move with the human CLI every 1.5 minutes.
3. Watch the Claude QA leader session every 5 to 15 seconds. If it stalls, hits API errors (No response from API) or is stuck retrying, restart it immediately. It must never again retry for 20 minutes.
4. Upwork timer: its recorded time must be safe. Detect that the timer is truly recording, not just running. Upwork also drops when the internet drops, and unrecorded work time is lost money.
5. If the Mac loses power nothing can run. After power returns, restart everything and log the gap.

## YOUR JOB NOW (step 1 only): study and verify Upwork. Do this FIRST. Build nothing else yet.
Hassan said: "first do all kind of testing and verification and learning for the upwork." Upwork is a NATIVE app, so use the human CLI (human focus Upwork, human see --app Upwork, human read, human find, screencapture then look at the image). Goals:
- Find out what the Upwork Desktop app looks like when the timer is RECORDING properly (timer counting, tracking state, any synced or connected text, the contract name).
- Find out what each broken state looks like on screen: no internet, offline, paused, stopped, not tracking, error banner, syncing, "will sync later". Hassan can unplug or switch Wi-Fi off for a test if you ask him first, but never do that yourself.
- Work out a reliable way to read the state with human read or OCR or the app's accessibility tree (human see --app Upwork), and test it repeatedly so it is trustworthy.
- Check where Upwork keeps local logs or cache (look, do not change) that could show whether time is being recorded or is queued offline.
- Write findings to docs/qa/UPWORK-FINDINGS.md: a short checklist, one fact per line, each fact verified by a command or a screenshot you looked at. Anything unverified says "to check".
- HARD RULES: NEVER click Start, Stop, Pause, Resume, Add manual time, or change any setting in Upwork. Never edit time entries. Only look. Hassan decides later whether the watchdog may restart the timer. Do not copy anything private (names, rates, earnings, messages) into files.
- Do not use the Upwork MCP tools to change anything.

## THEN (only after Hassan reviews UPWORK-FINDINGS.md): build the watchdog in ~/dotfiles/bin or this repo's scripts (ask Hassan where), as one script run by launchd, test each part, and show command output.

## The QA audit (paused while you study Upwork)
The human CLI is shared: Upwork study and the Safari QA both move the mouse and focus apps, so do NOT run QA ticks at the same time. The QA is paused. Facts:
- Audit file: docs/qa/2026-11-14-safari-audit.md (115 open issues, an Action list at the top, a Part 3 section). Previous handoff: docs/qa/LEADER-HANDOFF.md. Tick rules: /private/tmp/claude-501/-Users-hassanjan-ehtisham-all-projects-next-shadcn-dashboard-starter-main/b7c3c597-e2ca-4816-a320-0906aa6ca1d9/scratchpad/qa-tick.md. Tick script: /private/tmp/claude-501/-Users-hassanjan-ehtisham-all-projects-next-shadcn-dashboard-starter-main/b7c3c597-e2ca-4816-a320-0906aa6ca1d9/scratchpad/tick.sh. State: /private/tmp/claude-501/-Users-hassanjan-ehtisham-all-projects-next-shadcn-dashboard-starter-main/b7c3c597-e2ca-4816-a320-0906aa6ca1d9/scratchpad/qa-state.env (END_EPOCH is the original stop time, now past). Pages list: /private/tmp/claude-501/-Users-hassanjan-ehtisham-all-projects-next-shadcn-dashboard-starter-main/b7c3c597-e2ca-4816-a320-0906aa6ca1d9/scratchpad/qa-pages.txt.
- QA was running as a 4 minute CronCreate job; leader 2 (Herdr terminal t1y, resumable with: claude --permission-mode auto --resume 3d3a26fa-cf0e-4e43-9589-d6a15267f1de) ran ticks from about 12:46 to 17:46, then the connection dropped and checks stalled; log shows a gap from 17:46 to 23:22. A tick at 23:22 was invalid because Herdr was in front, not Safari.
- Total so far about 20 hours of checks across parts 1 to 3, about 290 page visits, 115 issues. The user wanted a further 20 hours (Part 3 started 11:48 PKT 15 Nov). Resume QA AFTER the Upwork study and the watchdog exist, with a new END_EPOCH of 20 hours of valid checks.
- Safari is signed in to https://gcs-portal-next.vercel.app as the verify account (sign in by clipboard only: VERIFY_USER_EMAIL and VERIFY_USER_PASSWORD from .env.local, pbcopy then cmd+v, never type the password with human; the login form shifts about 30px after a failed attempt, read the screen before clicking).
- Most urgent audit finding (do not repeat the numbers anywhere): the Financials page, Card reference tab, shows a full company Amex number with expiry and security code in plain text. Hassan has been told. Never write card numbers into files; delete screenshots that show them.
- Safety rules for QA: read only; never click Save, Delete, Sync, Reload on Financials, Reveal, Connect, Approve, Invite, Import; Find PO is a page check only (never scan a box, AfterShip quota); keep clicks out of the top right corner of the screen where macOS notifications cover the portal bell.

## Working style rules from Hassan's global instructions
- Never commit, never push, unless asked. No Co-Authored-By and no AI footers anywhere.
- No em dash or en dash characters anywhere in files or messages.
- Research subagents use model sonnet. Verify things yourself with commands, never claim a fix without visible evidence.
- Comments in code only where they explain WHY. Keep scripts short.
- When using hc to start workers: after sending a message, read the screen to confirm it started.

## First actions for you
1. Read this file, then docs/qa/LEADER-HANDOFF.md and the last 40 lines of the audit log.
2. Tell Hassan in 5 short lines what you understood and that you are starting the Upwork study.
3. Start the Upwork study (human see --app Upwork). Report back with short checklists as you learn things.
