---
name: workers
description: Start, watch and check Claude worker sessions in cmux the same way every time. Use whenever you are a leader handing work to another Claude session, starting a worker, asking "what is going on", "is the worker working", "status of the workers", "which workers are idle", or before reporting a worker's progress. Uses the dotfiles scripts cw-new and cw-board.
---

# Workers: start them right, watch them always

Two scripts in `~/dotfiles/bin` (on PATH): `cw-new` starts a worker, `cw-board` shows every worker's real state. Use them; do not hand-roll cmux commands for these jobs.

## Start a worker: `cw-new`
```
cw-new --name "K20 Small parts" --dir ~/Passenger-ds-K20 --branch chore/design-system-k20-small-parts \
       --repo ~/Passenger-ds-B --app passenger-app \
       --env-from ~/Passenger-ds-B/passenger-app/.env.local \
       --baseline-from ~/Passenger-research/tailwind-migration/screenshots \
       --baseline-to ~/Passenger-research/tailwind-migration/screenshots-K20 \
       --model claude-fable-5-1 --brief ~/Passenger-worker-briefs/K20.md
```
It makes the worktree from `--base` (default origin/staging), its own free port and test baseline, runs npm ci, opens the cmux workspace in the project's group and colour (`cmux-autocolor`), turns on `/remote-control`, sends the brief, and confirms each step on screen. Write the brief file first. Name the workspace with the tracker id first ("K20 ..."), so the board can find its tracker row.

## Watch: `cw-board`
- One look: `cw-board --match '~/Passenger-*' --tracker ~/Passenger-research/tailwind-migration/TRACKER.md --app passenger-app`
- Live pane for the human: the same with `--watch 60`, in a pane of the leader's workspace.
- Leader background watch: the same with `--alerts 60`, run with the Monitor tool (timeout 30 minutes, re-arm when it expires), so each new flag arrives as its own notification. A plain run_in_background only notifies when it ends.

Flags and what to do:
- `ready for review`: check the work yourself (diff, check:quick, pictures), report to the human with pictures.
- `idle but tracker says RUNNING`: read its screen; it is stuck, waiting on a question, or forgot the tracker. Unstick it.
- `text in input box`: a message did not send, or a ghost suggestion. Never press Enter on text you did not type; clear it with backspaces, then resend.
- `dev server :PORT down`: restart `npm run dev:test` in that worktree if the worker still needs it.
- `load N HIGH` (over 30): pause the next full check until it drops; never more than 3 workers.

## Rules this replaces nothing of
The global CLAUDE.md worker rules still apply: confirm a worker started after every message, keep a background watch, verify results yourself, report at once with pictures. These scripts are how you do that reliably.

## Close a worker
When its PR is merged and the board shows dirty 0 and +0: close its cmux workspace, then `git worktree remove` its folder (save any uncommitted work as a patch in the project's research folder first).
