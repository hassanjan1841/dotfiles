# human-input — handoff

Everything known about this project, including the mistakes, because the mistakes are
the expensive part. Written 2026-08-03.

---

## 1. What it is

Two programs that let a machine be operated the way a person operates it.

| | Role |
|---|---|
| `human` (Swift binary) | **Executes. Decides nothing.** Moves the pointer, clicks, drags, types, reads the screen. |
| `human-do` (Python) | **Decides. Executes nothing.** Describes a task in words, produces a plan, hands it to `human`. |

Either works alone. The split is deliberate — the thing that acts should have no opinions.

### Where it lives

```
~/dotfiles/human-input/
  human.swift      ~2000 lines, the whole binary
  human-do         the planner
  build.sh         builds + runs selftest (--no-test to skip)
  make-app.sh      wraps it in a signed Human.app
  README.md        user-facing reference
  HANDOFF.md       this file
~/dotfiles/bin/human      -> symlink, already on PATH
~/dotfiles/bin/human-do   -> symlink
~/tools/human-input       -> symlink to the dotfiles dir (old path, still works)
```

Repo: `hassanjan1841/dotfiles`. **Push over SSH** — `git push git@github.com:hassanjan1841/dotfiles.git HEAD:main`. HTTPS resolves to the `codebytesss` credential and 403s.

Build artefacts (`human`, `Human.app/`) are gitignored; the source is tracked. A fresh
clone needs one `./build.sh`.

---

## 2. The machine this was built and verified on

- MacBookAir10,1 — M1, 2020, **8 GB RAM**
- Single display, 1680×1050 points / 2560×1600 Retina. **Multi-display is deliberately unsupported.**
- macOS 26.5 (Darwin 25.5.0)
- Terminal: **WezTerm**, config at `~/.wezterm.lua` (also tracked at `dotfiles/wezterm/.wezterm.lua` — the two have drifted since July)
- Permissions, all granted: Accessibility, Screen Recording, Input Monitoring
- `claude` CLI at `/opt/homebrew/bin/claude` — this is what `human-do` plans through
- No `anthropic` Python SDK, no `ANTHROPIC_API_KEY`, no `ant` CLI, no Ollama
- `timeout` is **not** installed (use `perl -e 'alarm shift; exec @ARGV' N cmd`)

---

## 3. Commands

```
see        check | where | front | see | find | read | snip | find-image | pixel
           pane list|read|send|waitfor | waitfor | changed | state | dialog
act        focus | move | click | drag | scroll | type | key | text | gesture
           window where|move|place|resize | open | wait | idle
scripts    record | plan | run
safety     stop | go | unstick | selftest
```

Global flags on any action: `--require <App>`, `--dry`, `--persona <name>`,
`--device mouse|trackpad`, `--precise`, `--fallible`, `--ocr`, `--fast`,
`--expect-change [region]`, `--expect "text"`, `--retry N`, `--recover`.

Exit codes: `1` not found · `2` bad arguments · `3` no Accessibility · `4` wrong app in
front · `5` aborted by the stop flag · `6` wait timed out · `7` secure input on ·
`8` action had no visible effect · `9` typed text did not land · `130` terminated.

---

## 4. How the human motion model works, and why each part is there

Everything below was arrived at by measuring, not by taste. **Smooth easing is what
makes synthetic motion look synthetic** — the fixes were structural, not cosmetic.

- **Ballistic throw plus corrective submovements.** A fast primary movement that misses
  by an amount growing with the distance thrown, then one or two corrections. This
  structure is what reads as a person; a single smooth sweep never does.
- **Whole pixels at a fixed ~8 ms poll.** A real mouse reports at 125 Hz in whole
  pixels: the *interval* holds steady and the *deltas* vary. Sub-pixel interpolation on
  a jittery clock is the exact opposite, and is the single biggest tell.
- **Asymmetric velocity** — accelerates hard, decelerates longer. A symmetric bell is a
  tween.
- **Smooth positive-only rate noise**, so velocity wobbles around the curve. Must stay
  positive: an earlier version let progress go *backwards* and the pointer stuttered.
- **Tremor at 8–12 Hz**, where physiological hand tremor actually sits, with the wrist
  drifting under it at 1–3 Hz. Frequencies in **real seconds**, not in path progress.
  Amplitude stays sub-pixel — a whole pixel of shake at 10 Hz is visible shimmer.
- **Never sets event deltas.** With an absolute cursor position the system applies
  pointer acceleration *on top of* the warp and the cursor visibly fights itself.
- **Fitts' law budget covers the whole movement including corrections.** Spending the
  full budget on the throw and adding corrections after makes everything ~2× slower
  than a person, which reads as a camera pan.
- **Deadline pacing.** Asking for an 8 ms sleep gets ~10 ms on macOS; pacing by sleep
  alone stretches every movement by a quarter.
- **Hovering before acting.** Converging and firing instantly is the clearest bot tell.

Typing: lognormal inter-key intervals; alternating hands faster than same hand, same
finger slowest; a pause mixture from writing research (word retrieval ~330 ms, phrase
boundary ~735 ms, planning ~2.7 s); error mix from typing corpora (substitution 39 %,
insertion 33 %, omission 18 %, transposition 11 %).

Behaviour: familiarity (repeat visits faster, persisted), session shape driven by work
done rather than the clock, `--device trackpad` steadier than mouse, idle in episodes
(reading / scanning / busy / away) rather than a steady drip.

**Measured:** 1400 px crossing in **0.84 s** against Fitts' 0.86 s predicted. Typing
asked 70 wpm → 68.9 / 70.3 / 72.9 measured. Pointer worst miss 2.2 px over 20 moves.

---

## 5. Seeing — three tiers, chosen automatically

1. **Exact text.** `wezterm cli get-text` for terminals; Claude Code transcripts on disk.
   Preferred whenever the target is a terminal.
2. **Accessibility tree.** `see` / `find` / `state`. Exact rectangles, instant.
3. **Pixels.** `read` (screencapture + Apple Vision OCR), `find-image`, `pixel`.

Verification prefers the tree and falls back to pixels **automatically**: an app whose
tree carries no text *inside its window* (a terminal drawing on the GPU) gets the pixel
path, because trusting its tree would mean never seeing the thing you care about.

OCR agreed with the tree to 1 px (84,14 vs 84,15 for a menu item).

---

## 6. Every bug found, and the lesson

This is the section worth keeping. **Every single one was found by running the thing,
never by reading the code.** The build was clean each time.

### Motion
1. Bézier control points bowed off-screen, got clamped, and the cursor parked on the
   border then snapped back. → Clamp the control points, not the symptom.
2. Progress jitter could move the pointer **backwards** mid-flight. Stutter reads worse
   than a clean curve.
3. Fitts budget applied to the throw only → everything ~2× too slow.
4. `Thread.sleep(8 ms)` really takes ~10 ms → deadline pacing.
5. Event deltas + absolute position → the cursor fights itself (visible flicker).
6. Tremor above half a pixel at 10 Hz → visible shimmer, not tremor.

### Typing
7. An insertion slip could **double a space**, and macOS turns two spaces into ". ".
   Slips now only happen on letters.
8. Autocorrect rewrites a word while a correction is mid-flight. Corrections never
   cross a space. **Measured: 8/8 exact with autocorrect off, occasional differences
   with it on.** `--accuracy clean` where the exact string matters.

### Safety
9. `--hold` never recorded which key it held, so SIGTERM left the key down and macOS
   auto-repeated it forever. *(This is what made the arrow key look broken — see §9.)*
10. The signal handler did the cleanup itself, which is not safe in signal context. It
    now only raises a flag; cleanup happens at the next pause.
11. SIGKILL cannot be caught — a `kill -9` mid-keypress still leaves a key down.
    `human unstick` is the remedy.

### Scripts and rehearsal
12. **`waitfor` called `exit(0)` on success.** Standalone that is correct; inside `run`
    the steps share a process, so a successful wait silently ended the script partway
    **with a success code**. Same for `changed`, `pane waitfor`, and dismissing a
    dialog when none was present. The worst shape a bug can take.
13. Rehearsals actually waited — a plan with a 30 s wait polled for the full 30 s and
    then reported a failure for something that was never going to happen.
14. `idle --dry` never returned and burned a core: it measured itself against the wall
    clock while accumulating simulated time.
15. A `changed` case was inserted into the `pane` sub-switch, because two `case "read":`
    existed and the first match won. The command was simply unreachable.
16. The help text drifted several commands behind the code.

### Verification and change detection
17. **The baseline was captured *after* the action**, so it could never see the change
    it was meant to prove. It only appeared to work because a blinking caret supplied
    false positives.
18. Cells sampled single pixels → text strokes fell between samples and a whole
    sentence registered as nothing. Cells now average their area.
19. The grid was a fixed *count*, so sensitivity depended on region size. Cells are now
    a fixed **size in pixels**.
20. Exact-equality comparison counted one quantisation step of capture noise as change.
21. A fading caret has **four** states, not two, so no set of baseline samples covers
    it. Cells that flicker during the baseline are masked out instead.
22. A detected change is now confirmed a beat later, so a rendering blip is not news.

### Image matching
23. Average pixel difference scored unrelated dark regions at **0.92** — on a dark
    screen everything is within a few grey levels of everything else. Normalised
    cross-correlation instead.
24. A coarse pass that point-samples every k-th pixel misses the true peak when it
    falls between grid points. Averaged pyramid instead.

### Environment traps (not our bugs, but they cost hours)
25. **App names can contain invisible characters.** WhatsApp's begins with U+200E, so
    exact name matching never found it and `--require WhatsApp` would have silently
    refused forever. Names are now compared with directional marks stripped, and bundle
    identifiers accepted.
26. **Scroll acts on whatever is under the pointer.** Pass `x y` or nothing happens and
    nothing complains.
27. **An AX text area inside a scroll view reports the whole document height** (5254 px
    in testing), not the visible box. Aim at the **scroll area's** rect.
28. **A sheet is a child element with role `AXSheet`**, not an attribute on the window,
    and it can hang off a window that is not the focused one.
29. **A sheet does not block input, it absorbs it.** Keystrokes meant for the document
    land in the save panel's filename field, the screen changes, and the action *looks*
    like it worked. `--recover` clears the way **before** acting.
30. `NSWorkspace.frontmostApplication` never updates in a process with no run loop
    running — pump it while waiting.
31. `open -a Foo` from a tool-run shell dies with the shell and takes the new window
    with it. Ask the running app instead:
    `osascript -e 'tell application "TextEdit" to open POSIX file "..."'`.
32. `hidutil property --set` **silently does nothing** on this Mac's internal keyboard
    even with `--matching`; it reports success and `--get` reads the value back.
33. `claude -p` reads piped stdin and swallowed the keystroke meant for an approval
    prompt. Its stdin is now closed.
34. Importing Swift's `Carbon` module collides with names used here (it defines its own
    `typeText`). The one function needed is declared by hand and linked with
    `-framework Carbon`.
35. `CGDisplayCreateImage` is **removed** in this macOS. `screencapture` is used instead
    (ScreenCaptureKit is an async stream API, awkward for a one-shot tool).

### WhatsApp, found by sending one real message
39. **`NSRunningApplication.activate` is ignored by WhatsApp** on macOS 26. `focus`
    failed by name *and* by bundle id while Chrome, TextEdit and Finder all worked, so
    it read like a name-matching bug — it was not; `appMatches` strips the U+200E fine.
    An Apple Event still activates it. `focusApp` now waits 1.5 s for the cooperative
    path and then asks the other way.
40. **Ghost elements — the tree publishes two lists at once.** This first looked like a
    stale tree: after a search filtered the chat list, `see` still reported the old
    unfiltered chats. It is worse than staleness. WhatsApp keeps publishing the *old*
    rows alongside the new ones, so `Family grup🥰` sits at y=208 and the real
    `HASSAN JAN. HJ` at y=213 — two elements, five pixels apart, both claiming to be
    there. Nothing in the tree tells them apart. `AXUIElementCopyElementAtPosition`
    does, because it answers with what a click would actually hit, so `find` now hit
    tests its leading candidates and returns nothing rather than a ghost's rectangle.
    Verified: `Family grup` and `Maaz Husain` both exit 1 while the list is filtered.
    `AXManualAccessibility` was tried first and A/B tested — a no-op here, so it is not
    in the code.
41. **A "business chats that use AI from Meta" sheet absorbed the Return.** `key return`
    reported success, the message sat unsent in the compose box. This is §29 again in
    the wild: the sheet does not block input, it eats it. Anything that *sends* wants
    `--recover` and `--expect-change`, never a bare `key return`.
42. **`find` matched a message bubble, not the chat.** `find "Hassan Jan"` returned the
    coordinates of a "Replying to HASSAN JAN" bubble inside the open group. Clicking it
    blind would have sent to a family group. Search by the app's own search field and
    confirm the header before typing.

### Test bugs (mine, and they matter)
43. **A test string sent a real message to a real group.** Testing `wa-send`'s refusal
    guard, "Vu hacks" was passed as a name assumed not to be a chat. It is one — a
    forty-character group title that a two-word substring matches. The guard worked
    perfectly and sent, because that is what it is for. Deleted for everyone within
    minutes, but the lesson is structural: **there was no way to exercise the flow
    without sending.** `wa-send --dry` now resolves the chat, prints the header it
    landed on, and stops before typing. Test names should be nonsense, not plausible.
36. The selftest failed whenever a hand touched the mouse mid-test — it read as a 562 px
    failure. It now retries; the check is about the tool's aim, not the user's.
37. A sweep reported three commands "ok" that were never tested, because `timeout` does
    not exist here and I was grepping the shell's error message.
38. A device-profile comparison was confounded by familiarity — both runs used the same
    target, so the second was faster regardless. The README claim was wrong and was
    corrected (0.89 vs 0.95, not 0.71 vs 0.95).

---

## 7. What is verified, with numbers

| Thing | Evidence |
|---|---|
| Pointer accuracy | worst miss 2.2 px over 20 moves; 0.0 px typical |
| Pointer timing | 0.84 s / 1400 px vs Fitts 0.86 s |
| Trace realism | 151 events, 10 ms median gap, all whole pixels, 1–25 px steps |
| Typing speed | asked 70 → 68.9 / 70.3 / 72.9 wpm (clean mode) |
| Typing exactness | 300/300 dry, 8/8 and 6/6 in TextEdit |
| Keycode typing | `Q3 net profit: $12,450 (up 8%) -- check Amazon & Walmart!` exact |
| Modifiers | `shift+right ×5` selected exactly 5 chars; `cmd+tab` switches apps |
| Drag | text selection; window resize +160×+90 exact; corner move +142/+89 |
| Scroll | visible range 1–1161 → 4893–6132 |
| Sight | `click "Format"` opened the menu (0 → 8 items) |
| OCR | menu item at 84,14 vs tree's 84,15 |
| Change detection | 6/6 quiet on a still screen; 4/4 on two typed chars in a window |
| Verification | 3/3 verified; no-op correctly exits 8 |
| Image matching | known-offset target found exactly, score 1.000 |
| Secure input | `type` refused with exit 7 while secure input was on |
| Recording | recorded session replayed and produced the same document |
| `human-do` | described task → 8 steps → correct document |
| Chrome | focused, clicked a tab **by name**, verified, read page text |
| WhatsApp send | searched, opened the right chat of two, sent, ✓✓ delivered |

---

## 8. Known limitations

- **Multi-display unsupported** by choice — everything clamps to the built-in screen.
- **Secure input fields cannot be typed into.** macOS refusing, not a defect. A virtual
  HID driver (Karabiner-style DriverKit) is the only way past it. **`sudo` in a terminal
  is *not* secure input** — that works fine (verified).
- **Synthetic, not hardware.** Apps cannot tell; macOS can. That distinction is why the
  point above exists.
- **Image matching finds what a thing looks like, not which one you meant.** Blank
  background matches everywhere; every macOS window has identical traffic lights. Use
  distinctive targets and `--region`. Appearance also changes with focus and hover.
- **Verification costs ~2–3 s** when it falls back to pixels (baseline must span a caret
  blink). Free when the accessibility tree can answer.
- **Change detection blind spots are permanent for that check** — anything animating
  during the baseline is masked out.
- **A change that reverts within 0.35 s is ignored** (the confirmation window).
- **`human-do` decides, and can be wrong.** The approval gate is the control. Read the
  plan, especially for anything outward-facing.

## Untested

- Most Electron apps beyond WhatsApp and Chrome
- The fatigue curve (needs a 15+ minute continuous run)
- `Human.app` under launchd (needs its own Accessibility grant)

---

## 9. Things done to this machine, and how to undo them

- **`~/.wezterm.lua`**: added a guard so the autosave timer stops stacking on every
  config reload. The unguarded `call_after` started a new chain per reload and they
  never stop — a suspected cause of pointer stutter. **Existing chains only clear on a
  WezTerm restart, which has not happened yet.**
- **`hidutil` remap and its LaunchAgent: removed.** They did nothing on this Mac.
- **The arrow-key scare:** I claimed the right arrow was physically stuck. **That was
  wrong.** `hidSystemState` counts events posted to the HID tap — which this tool had
  been doing all evening — so the reading was contaminated. A clean 20-second test with
  hands off showed **zero** phantom input and no drift. The key feeling light is
  mechanical (worn or dirty switch); compressed air at 75° is the fix. No software
  remap is needed and none is installed.
- Clipboard was saved and restored around testing. No test documents left open.

---

## 10. Open question for the user

Their global `CLAUDE.md` says: *"For any live browser verification, ALWAYS use headless
Playwright MCP."* That contradicts their later instruction that everything should be
driven visibly with real cursor and keyboard. **Unresolved.** Suggested split: `human`
for doing work in apps, Playwright for verifying GCS Portal UI changes (headless is
faster and works in CI). Their call; `CLAUDE.md` should be amended either way.

---

## 11. What is left

**Reliability** — screen-region cache keyed to change detection (partly done for OCR).
**Realism** — pointer follows intent (drift toward the next target); recoverable
mistakes tied to Fitts rather than a flat rate; reading behaviour coupled to real work.
**Coverage** — upscaled OCR for small text; fuzzy matching for OCR misreads (`l` vs `1`);
real-keycode path already exists (`--keys`); Open/Save panels; trackpad pinch/swipe are
attempted but only indirectly evidenced.
**Robustness** — signed `.app` with its own permissions; automatic selftest already runs
on build.

**Deliberately not done:** multi-display; a model inside the binary (the deciding layer
is `human-do` or the conversation).

---

## 12. How to work on it

```bash
cd ~/dotfiles/human-input
./build.sh                    # builds and runs the selftest
human selftest                # six checks
human type "..." --dry --repeat 300   # 300 typing runs in a second, must be exact 300/300
human run script.human --dry  # rehearse anything, touches nothing
```

**The one rule this project earned:** a clean build, a green selftest and a passing
sweep prove nothing. Run the actual command against the actual app and look at the
result. Every real bug in §6 survived everything except that.
