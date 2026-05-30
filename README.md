# dotfiles

Personal dotfiles for Ubuntu and macOS, managed with [GNU Stow](https://www.gnu.org/software/stow/) and [chezmoi](https://www.chezmoi.io/).

![CI](https://github.com/hassanjan1841/dotfiles/actions/workflows/test.yml/badge.svg)

## What's included

| Package | Files |
|---|---|
| `bash` | `.bashrc` |
| `zsh` | `.zshrc` (Oh My Zsh + Powerlevel10k) |
| `git` | `.gitconfig` |
| `dev` | `.devrc` (project path config) |
| `tmux` | `.tmux.conf` (Tokyo Night theme, vi bindings, TPM) |
| `p10k` | `.p10k.zsh` (Powerlevel10k prompt config) |
| `tmuxinator` | `~/.config/tmuxinator/workspace.yml` |
| `zed` | `~/.config/zed/settings.json` + `themes/` |
| `claude` | `~/.claude/settings.json` + `CLAUDE.md` |

## Bootstrap a new machine

### Step 1 — Install Ansible + just

**Ubuntu:**
```bash
sudo apt install ansible
curl -fsSL https://just.systems/install.sh | sudo bash -s -- --to /usr/local/bin
```
**macOS:**
```bash
brew install ansible just
```

### Step 2 — Clone and run

```bash
git clone https://github.com/hassanjan1841/dotfiles.git ~/dotfiles
just install
```

`just install` runs `ansible-playbook setup.yml --ask-become-pass` — prompts **once** for your sudo password, uses it for all apt/system tasks silently.

> On macOS most tasks use Homebrew and don't need sudo at all.

### Step 3 — Add your secrets

```bash
nano ~/.secrets
# Add: export TAVILY_API_KEY="your-key"
#      export RESTIC_PASSWORD="your-backup-password"
```

### Step 4 — Install Tmux plugins

Open tmux and press `Ctrl+A` then `I` to install all TPM plugins.

### Step 5 — Install Zed themes

Open Zed → `Ctrl+Shift+P` → `zed: install extension` → search for your theme.
Any custom theme JSON files saved to `~/.config/zed/themes/` are auto-synced via dotfiles.

## Just commands

| Command | What it does |
|---|---|
| `just install` | Run Ansible playbook (prompts for sudo once) |
| `just update` | Pull latest from GitHub + re-run Ansible |
| `just sync` | Commit all changes with timestamp + push to GitHub |
| `just link` | Re-apply all stow symlinks |
| `just backup` | Backup dotfiles + project to `~/backups` via restic |

## Changing the project path

Edit one line in `~/.devrc` — startup.sh, tmuxinator, and just backup all pick it up:

```bash
PROJECT_PATH="$HOME/your-project"
```

## Startup workflow

`startup.sh` runs at login (GNOME autostart, 8s delay) and asks:

- **Dev Mode** — Chrome (Profile 9, restore session) + terminal window 1 (`npm run dev-server` + `claude`) + terminal window 2 (`claude`)
- **Chill Mode** — Chrome only

Logs at `~/.local/share/startup.log`. On macOS use `startup-mac.sh` (System Settings → Login Items).

## tmuxinator

```bash
tmuxinator start workspace
```

Window 1: `npm run dev-server` | Window 2: `claude`

## CI

GitHub Actions runs the Ansible playbook in `--check` (dry run) mode on every push to `main`, on both `ubuntu-latest` and `macos-latest`.

## Installed tools (via Ansible)

- **Shell:** zsh, Oh My Zsh, Powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting
- **Terminal:** tmux + TPM, tmuxinator, just
- **Node:** NVM, Node LTS, npm global tools (claude, vercel, typescript, pnpm, biome, opencode)
- **JS runtime:** Bun
- **Python:** uv, aider-chat
- **Editor:** Zed
- **CLI:** gh, chezmoi, stow, restic
- **Clipboard:** CopyQ
- **Media:** VLC
- **Browser:** Google Chrome
- **Remote desktop:** AnyDesk
- **VPN/DNS:** Cloudflare WARP
