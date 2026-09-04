# Driving WezTerm from Claude Code, use `wezterm cli`, never keystrokes

The reliable way to open, switch, or drive a terminal session in WezTerm is WezTerm's own
multiplexer CLI (`wezterm cli`). It addresses panes by numeric ID and talks straight to the
mux, so it does not care what is focused, what workspace is shown, or what modal dialog is up.

## Why NOT keystrokes / the `human` tool (learned the hard way, 2026-09-04)

Simulating keys to switch workspaces or launch a session fails on this Mac + WezTerm:

- **Option/Alt bindings never fire.** macOS composes `Option+j` into `∆` and `Option+4` into
  `¢` *before* WezTerm sees a modifier, so the workspace shortcuts (`Alt+j` fuzzy switcher,
  `Alt+1..9` direct jumps) are typed as junk characters into whatever pane is focused instead
  of switching anything.
- **Focus is ambiguous.** Several live Claude sessions run in one WezTerm; from the outside they
  look identical, so blind keystrokes can land in the wrong session (or in WhatsApp).
- **A leftover TCC permission dialog** ("WezTerm wants to control Terminal / AppleScript", from
  an earlier `osascript` attempt) is modal and eats all keyboard input until dismissed.

`wezterm cli` sidesteps all three: no modifiers, no focus, no dialogs.

## The commands

`wezterm` lives at `/opt/homebrew/bin/wezterm`. Run these from any pane inside WezTerm (the
`WEZTERM_UNIX_SOCKET` env is already set, so the CLI connects to the running GUI automatically).

```bash
# See every window / tab / pane with its workspace, id, title and cwd:
wezterm cli list

# Spawn a NEW WINDOW in a named workspace (this version REQUIRES --new-window with --workspace).
# Prints the new pane id (there may be a leading log line, take the trailing number):
wezterm cli spawn --new-window --workspace gcs-work- --cwd /path/to/repo

# Send text to a pane by id. --no-paste types it as if typed, not a bracketed paste.
# End with \r (carriage return) to submit a shell command or a Claude Code prompt.
printf 'claude\n'      | wezterm cli send-text --pane-id 106 --no-paste
printf '%s' "$PROMPT"  | wezterm cli send-text --pane-id 106 --no-paste   # type it
printf '\r'            | wezterm cli send-text --pane-id 106 --no-paste   # then submit

# Read a pane's current text (to verify a TUI booted, see output, etc.):
wezterm cli get-text --pane-id 106 | tail -20
```

## Recipe: open a new Claude Code session in a given workspace

```bash
WZ=/opt/homebrew/bin/wezterm
REPO=/Users/hassanjan/ehtisham-all-projects/next-shadcn-dashboard-starter-main
PANE=$("$WZ" cli spawn --new-window --workspace gcs-work- --cwd "$REPO" | tail -1)
printf 'claude\n' | "$WZ" cli send-text --pane-id "$PANE" --no-paste
sleep 14                                             # let the TUI boot
"$WZ" cli get-text --pane-id "$PANE" | tail -20      # confirm the ❯ input box is ready
printf '%s' "your first prompt here" | "$WZ" cli send-text --pane-id "$PANE" --no-paste
sleep 1
printf '\r' | "$WZ" cli send-text --pane-id "$PANE" --no-paste   # submit
```

It spawns a brand-new pane, so it can never disrupt an existing session. The user then views it
by switching to that workspace on their own keyboard (`Alt+4` = `gcs-work-`, or `Alt+j` → type
the name), where the real Option key works.

## Workspaces (from ~/.wezterm.lua, Alt = direct jumps)

`Alt+j` = zoxide fuzzy switcher · `Alt+1` dev · `Alt+2` crm-whatsapp · `Alt+3` propfix ·
`Alt+4` gcs-work- · `Alt+5` feature-tracker- · `Alt+6` all-rounder · `Alt+7` afri-invest-hub ·
`Alt+8` drawio-work · `Alt+9` auto-market · new tab = `Ctrl+Shift+T`. These are for the *human*
at the keyboard, not for automation. Automation uses `wezterm cli` above.

## Rule of thumb

When a target app exposes a real control API (like `wezterm cli`), use it instead of simulating
a keyboard. Simulated input fights the OS (modifier composing, focus, modal dialogs); the app's
own protocol addresses things by ID and does not.
