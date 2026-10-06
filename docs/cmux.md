# cmux setup

cmux is the main terminal on macOS. This repo gives it a shared look, colors and groups
workspaces by project folder, settles Claude's sidebar status, and adds the `human` GUI tool
with an optional screen glow.

## One-command setup

On a Mac (Apple Silicon, macOS with Homebrew):

```sh
xcode-select -p || xcode-select --install   # Swift compiler for glow and human; rerun after it finishes
git clone https://github.com/hassanjan1841/dotfiles.git ~/dotfiles
cd ~/dotfiles && just cmux
```

No `just` yet? `brew install just stow`. The full machine bootstrap (`bootstrap.sh` / `just install`)
runs `just cmux` for you on macOS.

`just cmux` is safe to rerun. It:

- checks for the Xcode Command Line Tools and Homebrew,
- installs the cmux app if it is missing,
- links `ghostty/` and `cmux/` into `~/.config` with stow (an existing real file is moved to `*.bak-<date>` first),
- copies `projects.example.json` to `~/.config/cmux/projects.local.json` if you have none,
- builds `glow/glow-overlay` and `human-input/human` when missing or older than their source,
- adds the Claude Code Stop hook to `~/.claude/settings.json` if it is not there yet.

Clone to `~/dotfiles`: `.zshrc` puts `~/dotfiles/bin` on PATH and the Stop hook points there.

## What each piece does

| Piece | Where | What it does |
|---|---|---|
| Look | `ghostty/.config/ghostty/config` | Theme, font, padding. cmux reads the Ghostty config. Apply edits with `cmux reload-config`. |
| Sidebar | `cmux/.config/cmux/cmux.json` | Accent and selection colors, sidebar rows, auto naming. Edits apply live. |
| Projects | `~/.config/cmux/projects.local.json` | Your own project folders, colors and icons. Personal, never committed. |
| `cmux-autocolor` | `bin/` | Gives a new workspace its project's color and group, and colors the group header. Runs from `.zshrc` in every cmux shell. |
| `cmux-tidy` | `bin/` | One-off cleanup: creates every project header and renames workspaces by the `rename` rules. |
| `cmux-stop-settle` | `bin/` | Claude Stop hook. cmux can leave a finished turn on "Running"; this re-sends a plain stop so it settles on "Idle". |
| `glow` | `bin/glow`, `glow/glow.swift` | Optional screen-edge glow while Claude drives the mouse or keyboard. Off by default. |
| `human` | `bin/human`, `human-input/` | Real OS-level clicks and keys for native apps. Lights the glow first when it is on. |

## Your projects

Edit `~/.config/cmux/projects.local.json` (start from `cmux/.config/cmux/projects.example.json`):

```json
{
  "projects": {
    "My App": {
      "folder": "~/code/my-app",
      "match": ["~/code/my-app", "~/code/my-app-*"],
      "color": "#7aa2f7",
      "icon": "building.columns.fill",
      "rename": { "~/code/my-app": "My App terminal" }
    }
  }
}
```

- `folder`: the project folder; the group header is created there.
- `match`: optional globs or folder prefixes; defaults to `folder`. Use it to pull worktree folders into the same group.
- `color`: hex; `icon`: an SF Symbol name.
- `rename`: only for `cmux-tidy`; maps a workspace title prefix to a new title.

Then color what is already open:

```sh
cmux-autocolor --all
```

Manual choices win: a workspace or header you colored, iconed or grouped by hand keeps it. To
recolor a header after changing its color here, run `cmux workspace-group set-color <group> --hex <color>`.

Why a separate file: cmux only reads `workspaceGroups.byCwd` from `cmux.json`, which is shared in
git. Keeping project paths out of it means the look stays shared and each person keeps their own
projects. `cmux-autocolor` still honors a `byCwd` block in `cmux.json` if you add one.

## Start Claude inside cmux

The cmux socket runs in `cmuxOnly` mode: only processes started inside cmux can talk to it. Start
Claude Code from a cmux tab, or `cmux-autocolor`, `cmux-tidy` and the Stop hook cannot reach cmux.
Do not loosen `automation.socketControlMode` to get around it.

## Stop hook

`just cmux` adds this to `~/.claude/settings.json` under `hooks.Stop` if it is missing:

```json
{ "hooks": [{ "type": "command", "command": "$HOME/dotfiles/bin/cmux-stop-settle", "timeout": 10 }] }
```

It does nothing outside cmux.

## human permissions

`human` sends real input, so macOS has to allow it. Permissions attach to the app that launches
it, so grant them to **cmux** in System Settings, Privacy & Security:

- **Accessibility**: required, for clicks, keys and reading the interface.
- **Screen Recording**: for screenshots and OCR.
- **Input Monitoring**: only for recording your own input.

Restart cmux after granting, then confirm:

```sh
human check
```

## glow

```sh
glow on      # glow the screen edge whenever human acts
glow off
glow test    # light it for 6 seconds to see it
```

## Personal values in this repo

`claude/.claude/settings.json` has a `CLAUDE_CODE_PLUGIN_DIRS` env pointing at the owner's own
plugin folders. It is personal; a partner does not need it and should not stow the `claude`
package for cmux. `just cmux` only touches the Stop hook in your own settings.
