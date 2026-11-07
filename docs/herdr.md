# Herdr

## On a new Mac
1. Install the Herdr app and open it once.
2. Run `just herdr` in `~/dotfiles`.
3. If the layout did not switch by itself, press ctrl+shift+L until "cmux-style" shows.

## What is tracked
- `layouts/cmux-style.json`: Herdr's main layout without the top tab bar; spaces sidebar on the left.
- `mods/spaces-tree/`: the sidebar. Each space lists its tabs under it, with a fold arrow, a + for a new tab and a dot on a tab that finished while you were not looking.
- `settings.json`: zoom, sounds, fonts.
- Everything else in `~/.config/herdr-app` is written by Herdr and stays out of git.

## Good to know
- Files and Changes panels: open them from the command palette (cmd+shift+P), since the top bar is hidden.
- Back to Herdr's own layout: ctrl+shift+L. Emergency reset: ctrl+alt+shift+escape.
- After editing the sidebar, run `herdr-app check ~/.config/herdr-app/mods/spaces-tree`.
- Herdr does not notice edits made here in dotfiles, because its files are links: run `touch -h ~/.config/herdr-app/mods/spaces-tree/main.js` (the edited file) to make it reload.
- A working tab shows a pulsing dot, not Herdr's spinning ring: Herdr 0.1.13 draws animations at about 11 to 19 frames per second, which makes a ring jump (measured 2026-11-08, reported to Herdr).
- Herdr can replace a link with a plain file when it saves; `just sync` copies it back into dotfiles and relinks.
- Workers: `cw-new` and `cw-board` work in Herdr and cmux (see `claude/.claude/skills/workers/SKILL.md`).
