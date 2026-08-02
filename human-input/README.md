# human

Drives macOS the way a person does. Curved pointer paths, real click dwell, uneven
keystroke rhythm, and mistakes that get noticed and fixed.

```bash
./build.sh          # rebuild after editing (links Carbon for the secure input check)
./make-app.sh       # optional: wrap it in a signed Human.app with its own permissions
human check         # every permission gate, screen size, cursor
```

`~/dotfiles/bin/human` symlinks to the built binary and that directory is already on
PATH, so a fresh clone needs one `./build.sh` and nothing else. The binary and the app
bundle are gitignored; the source is what is tracked.

## Commands

```
human check                       permissions, screen size, cursor position
human where / human front         cursor position, name of the frontmost app
human see [--app X] [--role R]    list what it can see, with coordinates
human find "Save" [--app X]       coordinates of a named thing, exit 1 if not there
human waitfor "Done" [--gone]     wait until something appears or goes away
human focus <AppName>             bring an app forward and wait until it really is
human move <x> <y>
human click <x y | "name"> [--right] [--double] [--precise]
human drag <x1> <y1> <x2> <y2> [--precise]
human scroll <amount> [x y] [--horizontal]
human type "text" [--wpm 70] [--accuracy clean|human|raw]
human key <name> [--cmd --shift --opt --ctrl]
human open <AppName> / human wait <seconds>
human idle [--minutes N] [--no-yield] [--verbose]
human run <file|-> [--verbose] [--dry]
human selftest                    prove pointer, typing, guard and sight still work
human stop / human go             set or clear the abort flag
```

Any command also takes `--dry` to rehearse without touching anything, and
`--persona <name>` to pin one consistent hand: same speed, same curve bias, same
error rate every run.

## Seeing, in three tiers

Exact beats recognised, so it goes in this order.

**1. Terminal panes.** WezTerm publishes nothing to accessibility because it draws on
the GPU, but its own CLI hands over the exact text and writes back without focus or
synthetic input:

```bash
human pane list                             # every pane with its id
human pane read 22                          # exact text of that pane
human pane send 22 "bun run build" --enter  # writes into it, no keyboard involved
human pane waitfor 22 "Compiled|error" --timeout 300
```

This is the right way to drive a terminal. It cannot land in the wrong window, because
it targets a pane id rather than whatever has focus.

**2. Accessibility tree.** Names rather than coordinates, exact rectangles:

```bash
human see --app TextEdit          # everything clickable, with coordinates
human click "Format"              # finds it and clicks it
human waitfor "Wrap to Page" --timeout 8
```

**3. Pixels.** For anything that publishes nothing: canvases, games, screen shares,
terminals. `screencapture` plus Apple's Vision OCR, offline and free, returning text
with coordinates so it can click what it reads.

```bash
human read --region 0,0,900,120 --fast   # text and coordinates, about 1s
human find "bypass permissions" --ocr    # falls back to pixels when the tree is blank
```

OCR is a fallback by design: `--ocr` only reaches for pixels when the tree cannot
answer. A full screen read at accurate quality takes about 3s, a small region with
`--fast` about 1s. Verified against the tree: OCR put the WezTerm menu at 84,14 where
accessibility said 84,15.

## Stopping it

Hold **control+option+command**, or run `human stop`, and any running action aborts
within about 50ms. If it was mid-drag it releases the button first rather than
leaving your mouse stuck down. `human go` clears the flag.

Add `--require <AppName>` to any action and it refuses to fire unless that app is in
front. Use it. Without it, a missing window means your keystrokes land wherever focus
happens to be.

## Knowing whether it worked

Verification asks the **app** what it publishes, not the pixels: exact, instant, and
blind to a blinking caret because a caret is not in the accessibility tree. Pixels are
the fallback, chosen automatically. An app whose tree carries no text inside its window
(a terminal drawing on the GPU) gets the pixel path, because trusting its tree would
mean never seeing the thing you care about.

```bash
human state                              # fingerprint of what the app publishes
human type "note" --verify               # read the field back; did the text land
human click "Save" --expect-change --retry 2 --recover
human dialog check                       # is a sheet sitting on top
human dialog dismiss                     # clears it, preferring the safe button
```

`--verify` on typing exists because sending keystrokes tells you nothing about whether
they arrived, and autocorrect can rewrite a word while a correction is still in flight.
Proven: catches the errors `--accuracy raw` leaves behind, no false alarms in clean
mode, and tolerant of an app capitalising a first letter by itself.

`--recover` clears a blocking panel **before** acting, not only after failing. A sheet
does not block input, it absorbs it: keystrokes meant for the document land in the save
panel's filename field, the screen changes, and the action looks like it worked.


An action that cannot tell whether it landed is a guess. Any action can be asked to
prove its effect and repeat itself when it cannot:

```bash
human click "Save" --expect-change 400,200,600,400 --retry 2
human click "Send" --expect "Message sent" --retry 1
human changed 400,200,600,400 --timeout 3     # or just watch a region
```

Change detection is a sampled perceptual hash of the region, quantised so antialiasing
and a blinking cursor do not count as change but a repaint does. It costs about 250ms,
against 1 to 3 seconds for OCR, which is why OCR results are cached against that same
hash and only re-read when the pixels actually move. Exit 8 means the action produced
no visible effect after its retries.

## Typing accuracy modes

- `clean` never mistypes.
- `human` (default) slips and corrects itself. Final text is always exact.
- `raw` leaves about one slip in six uncorrected, so the final text can differ.

`--keys` presses the actual keys instead of injecting characters. Slower and bound to a
US layout, but terminals, games and some Electron apps ignore injected unicode.

`--wpm` means net speed, what a typing test would report. Corrections are already
accounted for, so `--wpm 70` in human mode delivers roughly 70. Single sentences vary
a lot, between about 50 and 95, because one thinking pause moves the number. That
spread is the point.

Slips only happen on letters, never on spaces or punctuation, and a correction never
crosses a space. Both rules exist because macOS rewrites text behind your back:
two spaces become a period, and autocorrect rewrites a word the moment you leave it.

**Autocorrect can still beat it.** Measured in TextEdit: 8/8 exact with system
autocorrect off, and occasional differences with it on, where a word gets rewritten
while a correction is mid-flight. The slip logic itself is proven over 500 dry runs,
so this is the environment rewriting text, not the model. Where the exact string
matters, use `--accuracy clean`: nothing is mistyped, so nothing needs correcting and
there is nothing for autocorrect to collide with.

## What makes it read as a hand

The pointer model matters more than anything else here, and smooth easing is not it.
A tweened curve reads as animation no matter how pretty the easing is.

- **Submovements, not one sweep.** A fast ballistic throw lands near the target and
  misses by an amount that grows with the distance thrown, then one or two smaller
  corrections close the gap. That structure is what a person looks like.
- **Whole pixels at a real polling rate.** An ordinary mouse reports at 125Hz and only
  ever in whole pixels, so the interval stays put and the step sizes vary, between 1
  and 25px on a long throw. Sub-pixel interpolation on a jittery clock is the opposite,
  and it is the single biggest reason synthetic motion looks animated.
- **Tremor at 8 to 12Hz**, which is where physiological hand tremor actually sits, with
  the wrist drifting underneath at 1 to 3Hz. Frequencies in real seconds, not in path
  progress. Amplitude stays sub-pixel, because a whole pixel of shake at 10Hz is a
  visible shimmer.
- **Never sets event deltas.** With an absolute cursor position the system applies
  pointer acceleration on top of the warp and the cursor visibly fights itself.
- **Hovering before acting.** Converging on a target and firing instantly is the
  clearest bot signature there is.
- **Fitts' law with target width**, and the budget covers the whole movement including
  its corrections. Spending the full budget on the throw and adding corrections after
  makes everything about twice as slow as a person, and slow smooth motion is exactly
  what reads as a camera pan. Measured: 0.84s to cross 1400px, against 0.86s predicted.
- **Paced to a deadline, not by sleeping.** Asking for an 8ms sleep gets you about 10 on
  macOS, so pacing by sleep alone stretches every movement by a quarter.
- **An asymmetric velocity curve.** Aimed movement accelerates hard and spends longer
  slowing down. A symmetric bell is a tween.
- **Motor noise on the rate of travel**, smooth and always positive, so the velocity
  curve has a wobble in it and progress still never goes backwards.
- Long reaches sometimes stall partway while the eyes catch up.
- Keystroke gaps are lognormal, not uniform. Alternating hands are faster than one
  hand, and repeating a finger is slowest.
- Pause mixture drawn from writing research: word retrieval near 330ms, phrase
  boundaries near 735ms, occasional planning pauses of a couple of seconds.
- Error mix from typing corpora: substitution 39%, insertion 33%, omission 18%,
  transposition 11%.

## The parts that behave like a person, not just move like one

- **Familiarity.** Targets you have hit before are approached faster and with fewer
  corrections, and it remembers across runs. Measured: 1.03s on the first visit to a
  target, 0.71s by the sixth.
- **Session shape.** A slow start while warming up, a long steady middle, then a
  gradual slide in both speed and accuracy as it tires.
- **Device profile.** `--device trackpad` is steadier and more direct than the default
  mouse, because direct manipulation overshoots less. Measured with familiarity cleared
  and separate targets: 0.89s against 0.95s, about 6%. An earlier claim of 0.71s
  against 0.95s was wrong, confounded by the second run reusing a familiar target.
- **Idle in episodes.** Reading, scanning, busy work, and genuinely away from the desk,
  rather than a steady drip of movement. Reading tracks along a real line of text and
  nudges the page, because that is what reading looks like.
- **Typing that knows what it is typing.** Code is detected by symbol density and typed
  with its own rhythm: pauses hunting for brackets rather than at sentence ends, and a
  higher error rate. `--style prose|code|auto`.
- **`--fallible`** lets a click miss occasionally, notice, and correct. Off by default,
  because a stray click lands on whatever is really there.
- **`--next x,y`** starts the pointer drifting toward the next target after a click,
  the way a hand leads into what it is about to do.

## How you actually use it: plan, agree, run

Assign a task, read what it intends to do in plain words, say yes, watch it happen.

```bash
human plan reconcile.human        # the steps, in words, touching nothing
human run reconcile.human --confirm
```

```
reconcile.human, 7 steps
   1. bring TextEdit to the front
   2. press cmd+a, only if TextEdit is in front
   3. press delete
   4. type "Sellerboard reconciliation, 3 August", only if TextEdit is in front, read it back
   5. press return
   6. type "Account daily totals match the dashboard...", read it back, clear anything in the way first
   7. press s, only if TextEdit is in front
  about 17s at a human pace

run it? [y/N] y

[1/7] bring TextEdit to the front
[2/7] press cmd+a, only if TextEdit is in front
...
done: 7 of 7 steps in 20s
```

The duration is measured by rehearsing the script, not estimated. Answering anything
but yes does nothing at all. Every step is appended to `~/Library/Logs/human-input.log`
so a finished run can be read back afterwards.

## Scripts

One command per line, `#` for comments. Quoted text stays one argument.

```
focus TextEdit
key a --cmd --require TextEdit
key delete
type "Sellerboard reconciliation notes"
key return
type "Checked the account daily totals against the dashboard."
key s --cmd
```

```bash
human run notes.human --verbose
```

## Things that will bite you

- **Scroll acts on whatever is under the pointer.** Pass `x y` to put it over the
  right view first, or nothing happens and nothing complains.
- **Accessibility coordinates for a text area inside a scroll view are the whole
  document**, often thousands of pixels tall. Aim at the scroll area's rect, which is
  the visible box.
- **Small targets need `--precise`.** Aim jitter is about 2.5px and a window resize
  edge is roughly 4px, so a jittered grab misses and nothing resizes.
- **Only the main display.** Everything is clamped to it, by choice.
- **Never posts a click of its own accord.** `idle` only moves the pointer.
- **A vanishing pointer is usually the terminal, not this.** WezTerm defaults
  `hide_mouse_cursor_when_typing` to true, so the pointer disappears on every keystroke
  until the mouse moves. Set it to false in `~/.wezterm.lua`.

## Testing without a window

`--dry` models the screen buffer instead of posting events, and adds up the intended
delays instead of sleeping, so hundreds of runs finish instantly:

```bash
./human type "some sentence" --dry --repeat 500          # must be exact 500/500
./human type "some sentence" --dry --repeat 300 --wpm 80  # speed check
```

## Permissions, all of them

`human check` reports every gate at once. There are four that matter:

- **Accessibility** is the one that counts. It covers sending clicks and keys, and
  reading the interface. Pointer movement alone needs nothing.
- **Screen Recording** is only for pixel eyes, capture and OCR. Not needed otherwise.
- **Input Monitoring** is for *listening* to input, not sending it. Nothing here needs
  it today; it would matter for a global hotkey listener.
- **Secure Input** is not a permission you grant, it is a state an app turns on when a
  password field is focused. While it is on, keystrokes are silently swallowed. Typing
  refuses with exit 7 rather than sending half a sentence into a void.

Permissions attach to the app that launches this, so a binary run from your terminal
inherits the terminal's grants. Running it from cron or launchd means granting them
again for that parent. Bundling it as a signed .app would give it a stable identity of
its own, which is the proper fix and is not done yet.

## Keyboard

Modifiers are pressed as real `flagsChanged` events, not just flags stamped on a key
event. That distinction is not cosmetic: it is what makes `cmd+tab` possible at all,
and what makes shift+click extend a selection, because apps ask the system whether
shift is down *right now* rather than reading the event.

```bash
human key cmd+a                    # chords read the way people say them
human key shift+right --repeat 5   # modifier stays down across all five
human key cmd+tab                  # holds cmd across the tab press
human key down --hold 1.5          # holds the key, with real repeat rate
human click 400 300 --shift        # modifier held across the click
human click 400 300 --triple       # or --double, --right, --middle, --hold 0.8
```
