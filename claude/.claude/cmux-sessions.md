# Driving cmux from Claude Code: use the `cmux` CLI, never keystrokes

cmux (`/Applications/cmux.app`, CLI at `/opt/homebrew/bin/cmux`) is the main terminal on macOS
since 2026-10-03. It is built on libghostty, so its look comes from `~/.config/ghostty/config`
(stowed from `~/dotfiles/ghostty/`). WezTerm stays installed as the fallback; its recipe is
[wezterm-sessions.md](./wezterm-sessions.md).

## Access: only from inside cmux

The socket runs in the default `cmuxOnly` mode: only processes started inside cmux can connect.
A Claude session started in WezTerm or another app gets
`Access denied - only processes started inside cmux can connect`. So start Claude from a cmux
tab when it needs to drive cmux. Do not loosen `automation.socketControlMode` to get around it;
the other modes let any local process type into these terminals.

Launching is the one thing that works from outside: `cmux <path>` opens a directory in a new
workspace (and starts cmux if needed).

## Find your target

A window holds workspaces; a workspace holds split panes; a pane holds surfaces (terminal or
browser tabs). Refs look like `workspace:2`, `surface:4`.

```bash
cmux identify --json        # the caller's own window/workspace/surface
cmux tree --all --json      # everything, with refs
```

## The commands

```bash
# New workspace (does not steal focus by default) running a command.
# `new-workspace` is now an alias of `workspace create`; CMUX_QUIET=1 hides the notice.
cmux workspace create --name gcs-work --cwd "$REPO" --command claude

# Move a WezTerm/other-terminal Claude session into cmux: /exit it there first (never run
# one session in two places), then resume it by id (ids: ~/.claude/sessions/<pid>.json):
cmux workspace create --name "BOM export" --cwd "$DIR" --command "claude --resume <session-id>"

# Name, color and project header (group) for a workspace:
cmux workspace-action --action rename --workspace workspace:3 --title "TM warning"
cmux workspace-action --action set-color --workspace workspace:3 --color '#ff9e64'
cmux workspace-group create --name Passenger --cwd ~/Passenger-development --idempotency-key tidy-Passenger
cmux workspace-group add --group <group-ref> --workspace workspace:3

# New split in a workspace; browser panes take --url:
cmux new-pane --workspace workspace:2 --direction right --command 'bun run dev'
cmux new-pane --workspace workspace:2 --type browser --direction down --url http://localhost:3000

# Read before sending, and again after, to check the result:
cmux read-screen --surface surface:4 --lines 40

# Send text (\n or \r submits) and keys:
cmux send --surface surface:4 "your prompt here"
cmux send-key --surface surface:4 enter
cmux send-key --surface surface:4 ctrl+c
```

`cmux guide` prints the full agent guide; `cmux <command> --help` for flags. Verified in use on
2026-10-03: `workspace create --command`, `workspace-action rename|set-color`, `workspace-group
create|add`. `cmux-tidy` (in `~/dotfiles/bin`, on PATH) applies the project headers, plain names
and colors in one go; edit its PROJECTS and RULES lists for new work, it is safe to rerun.

## Recipe: open a new Claude Code session in its own workspace

```bash
REPO=/Users/hassanjan/ehtisham-all-projects/next-shadcn-dashboard-starter-main
cmux new-workspace --name gcs-work --cwd "$REPO" --command claude
cmux tree --all --json                       # find the new surface ref
cmux read-screen --surface surface:N --lines 20   # wait until the input box shows
cmux send --surface surface:N "your first prompt here"
cmux send-key --surface surface:N enter
```

It creates a new workspace, so it never disturbs an existing session. The human switches to it
from the sidebar or `Cmd+P`.

## Look and feel

- Theme, font, padding, cursor, blur: edit `~/dotfiles/ghostty/.config/ghostty/config`, then
  `cmux reload-config` (no restart). Check it with
  `/Applications/cmux.app/Contents/Resources/bin/ghostty +validate-config`.
- cmux-only settings (sidebar, notifications, automation) live in `~/.config/cmux/cmux.json`,
  stowed from `~/dotfiles/cmux/`; edits apply live. The sidebar hides paths, branches, PR rows,
  logs and SSH, shows the agent's latest notification in 2 lines, and AI-names new workspaces.
- Per-workspace name, project label and color: `cmux workspace-action --action
  rename|set-description|set-color --workspace <ref> ...`. Colors used: GCS `#7aa2f7`,
  Passenger `#ff9e64`, Customers Direct `#9ece6a`.
- Selected row: fill `#20406f` with accent `#7aa2f7` (`workspaceColors.selectionColor`,
  `app.accentColor`). Measured on screen 2026-10-03: title 10.4:1, subtitle 7.4:1, both WCAG
  AAA. cmux's default bright blue fill measured 3.2:1 and 3.0:1, which fails AA (4.5:1).
- Closing: cmux asks before closing a tab, workspace or window and before quitting, but a
  workspace with nothing running (an idle shell) closes without asking unless it is pinned.
- Shortcuts: `Cmd+N` workspace, `Cmd+T` tab, `Cmd+D` / `Cmd+Shift+D` split, `Cmd+P` go to
  workspace, `Cmd+Shift+U` jump to the latest agent waiting on you, `Cmd+Shift+L` browser.
