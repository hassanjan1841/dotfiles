---
name: go
description: Carry out the agreed plan to the end without stopping for check-ins, verify it, and stop before anything irreversible. Use when the user types /go, or says "ok go on", "follow the plan", "go ahead and tell me when it's done", "don't commit".
---

# Go

Work through the plan already agreed in this conversation (or the task in the args) to the end.

## While working
- Do not stop to ask about choices that have a sensible default. Pick it and note it.
- Stop and ask only for a real blocker: a decision that is the user's, missing access, or a failing check you cannot fix.

## Never without asking first
- `git commit`, `git push`, opening or merging a PR, deploying, sending messages to anyone, deleting data.
- When the work is ready for one of these, stop and ask. Show what would be committed or sent.

## Before reporting done
- Run the `verify` skill: the project's real checks and, for UI, the real flow. Report actual command output.
- Follow the `proof` skill: show evidence, not claims.

## When finished or blocked
- Send a PushNotification with one line: done, or what is blocking.
- Reply with a short checklist: what changed (`file:line`), check results, what still needs the user (for example "ready to commit, say yes").
