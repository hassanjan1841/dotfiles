# dotfiles

Personal dotfiles for Ubuntu and macOS, managed with [GNU Stow](https://www.gnu.org/software/stow/) and [chezmoi](https://www.chezmoi.io/).

## What's included

| Package | Files |
|---|---|
| `bash` | `.bashrc` |
| `zsh` | `.zshrc` (Oh My Zsh + Powerlevel10k) |
| `git` | `.gitconfig` |
| `dev` | `.devrc` (project path config) |

## Bootstrap a new machine

```bash
# 1. Apply dotfiles via chezmoi
chezmoi init --apply https://github.com/hassanjan1841/dotfiles.git

# 2. Install all tools via Ansible
ansible-playbook ~/dotfiles/setup.yml
```

## Manual setup (without chezmoi)

```bash
git clone https://github.com/hassanjan1841/dotfiles.git ~/dotfiles
cd ~/dotfiles
stow bash zsh git dev
```

## Changing the project path

The startup script and tmuxinator both read `~/.devrc`:

```bash
# ~/.devrc
PROJECT_PATH="$HOME/your-project"
```

## Startup workflow

`startup.sh` runs at login and asks which mode to open:

- **Dev Mode** — Chrome (Profile 9) + terminal window 1 (`npm run dev-server` + `claude`) + terminal window 2 (`claude`)
- **Chill Mode** — Chrome only

On macOS use `startup-mac.sh` instead (uses `osascript` dialog + Terminal.app).

## tmuxinator

```bash
tmuxinator start workspace
```

Opens two windows: `dev-server` (`npm run dev-server`) and `claude`.
