# Dev Environment Context

## Setup
- Ubuntu, GNOME Wayland, dotfiles at `~/dotfiles` → github.com/hassanjan1841/dotfiles
- Managed with GNU Stow + Ansible (`setup.yml`). Bootstrap: `bash <(curl -fsSL https://raw.githubusercontent.com/hassanjan1841/dotfiles/main/bootstrap.sh)`
- Justfile commands: `just install` (full setup), `just link` (re-stow symlinks), `just sync` (commit+push), `just update` (pull+re-run ansible)

## Terminal: WezTerm only
- Config: `~/dotfiles/wezterm/.wezterm.lua` (symlinked to `~/.wezterm.lua`)
- On startup: opens `dev` workspace, left pane = `npm run dev-server`, right pane = `claude`, Chrome (Profile 9) opens separately
- Startup script: `~/startup.sh` → `~/dotfiles/startup.sh` (GNOME autostart via `~/.config/autostart/`)
- No tmux/tmuxinator/ptyxis — WezTerm handles splits/tabs/workspaces natively

## Key WezTerm bindings
- `Ctrl+Shift+R` → resize mode (arrow keys) → Esc
- `Ctrl+Shift+Space` → quick select
- `Ctrl+Shift+↑/↓` → jump between prompts
- `Ctrl+Alt+-` → vertical split (top/bottom)
- `F2` rename tab, `Shift+F2` rename workspace
- `Ctrl+Shift+N/P` cycle workspaces, `Ctrl+Shift+$` workspace picker

## Rules — always do this after any change
1. If changing `startup.sh`: edit `~/startup.sh`, copy to `~/dotfiles/startup.sh`
2. All dotfile changes go in `~/dotfiles/` (stowed packages)
3. After every change: `cd ~/dotfiles && git add -A && git commit -m "..." && git push`
4. No Co-Author line in commits

## Project
- Active project: `~/speaklogic-testing` (set in `~/dotfiles/dev/.devrc` as `PROJECT_PATH`)
- Chrome uses Profile 9

## If something breaks
- WezTerm not splitting: check `~/.wezterm.lua` exists (run `just link`)
- Startup not running: check `~/.config/autostart/startup.desktop` exists
- Ansible changes: edit `~/dotfiles/setup.yml`, run `just install`
