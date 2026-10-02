---
name: verify
description: Prove that a change or a published page actually works before calling it done. Use when the user types /verify, says "verify", "test it", "make sure it works", or before reporting any code change, UI change or artifact as finished. Runs the project's real checks, drives the UI, and reports command output, not claims.
---

# Verify

The user cannot click-test. Never report "done" until every step below that applies has passed, and never hand back a "please click to check".

## 1. Know what changed
- Code: `git status --short` and `git diff` (plus `git diff --staged`). Read the whole diff.
- A page or artifact: read the file that was published.
- Write down the 3 to 6 things the change must do. Those are what you test.

## 2. Run the project's checks
Look in `package.json` scripts (or the Justfile/Makefile) and run what exists, in this order:
`format:check`, `lint`, `typecheck` (or `npx tsc --noEmit`), `test` / `test:unit`, `build`.
- Use the project's own package manager and scripts. In a fresh worktree run the install first.
- Report each command with its real result line (exit code, pass/fail counts). A check that could not run is reported as not run, with the reason.

## 3. Drive the real thing
- **Web page or app screen:** follow the user's GUI rule in CLAUDE.md (ask headless Playwright or `human` first, unless the user already said which). For a page Claude built itself, headless Playwright on a local copy is the default.
  - Click every button, tab and link the change touches; check the visible result, not just the DOM.
  - Check counts and text against the data, at desktop (1440x900) and phone (390x844) width; no sideways scroll.
  - Console: 0 errors from the page itself (Chrome DevTools MCP or Playwright console).
  - Apps with a database: use the local or test database, never live, unless the user says so.
- **Published artifact:** test a local copy first (serve it with `python3 -m http.server`), publish, then read the live version back and confirm it holds the fix.
- **Native app:** use `human` per CLAUDE.md.
- **CLI or script:** run it with real input and show the output.

## 4. Clean up
Stop servers you started, delete `.playwright-mcp/`, temp scripts, screenshots and copied env files. Nothing extra left in the repo.

## 5. Report (short checklist)
- Outcome first: works / does not work.
- Each check: command or action, then its real result.
- Anything not tested and why.
- Bugs found: fixed (with the re-test result) or listed for the user.
