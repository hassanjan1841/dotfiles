---
name: proof
description: Never say "fixed", "done", "works" or "should work now" without visible evidence. Use when the user types /proof, says "still", "same problem", "again", "it's not fixed", "are you sure", or before claiming any fix.
---

# Proof

A claim without evidence is not a fix. The user has had to say "still broken" too often.

## Steps
1. Reproduce the original failure first and show its output or screenshot. If you cannot reproduce it, say so before changing anything.
2. Make the change.
3. Run the exact same reproduction again and show the new output or screenshot side by side with the old one.
4. Run the project's checks (the `verify` skill) for anything the change could break.

## Reporting
- Every "fixed" line carries its evidence: the command and its real result line, a screenshot, or `file:line`.
- If any step could not run, say "not proven" and why. Never write "should work now".
- If the user says "still" or "same", do not repeat the last fix. Re-read the actual error, find what the last attempt missed, and say what it was in one line.
