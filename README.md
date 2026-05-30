# dotfiles

Personal dotfiles for Ubuntu and macOS, managed with [GNU Stow](https://www.gnu.org/software/stow/) and [Ansible](https://www.ansible.com/).

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
| `aliases` | `~/.aliases` (git, nav, dev, dotfiles shortcuts) |
| `taskwarrior` | `~/.task/` + `~/.timewarrior/` config |
| `wezterm` | `~/.wezterm.lua` |
| `zed` | `~/.config/zed/settings.json` + `themes/` |
| `claude` | `~/.claude/settings.json` + `CLAUDE.md` |
| `autostart` | `~/.config/autostart/startup.desktop` |
| `startup` | `~/startup.sh` (GNOME login launcher) |

## Bootstrap a new machine

### One-liner (recommended)

Paste this into a fresh terminal — prompts for sudo **once**, handles everything automatically:

**Ubuntu:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hassanjan1841/dotfiles/main/bootstrap.sh)
```
**macOS:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hassanjan1841/dotfiles/main/bootstrap.sh)
```

### Manual steps (if you prefer)

```bash
sudo apt install ansible                                              # Ubuntu
brew install ansible                                                  # macOS
curl -fsSL https://just.systems/install.sh | sudo bash -s -- --to /usr/local/bin  # Ubuntu just
git clone https://github.com/hassanjan1841/dotfiles.git ~/dotfiles
just install
```

### Step 2 — Add your secrets

```bash
nano ~/.secrets
# Add: export TAVILY_API_KEY="your-key"
#      export RESTIC_PASSWORD="your-backup-password"
```

### Step 3 — Install Tmux plugins

Open tmux and press `Ctrl+A` then `I` to install all TPM plugins.

### Step 4 — Install Zed themes

Open Zed → `Ctrl+Shift+P` → `zed: install extension` → search for your theme.
Any custom theme JSON files saved to `~/.config/zed/themes/` are auto-synced via dotfiles.

## Just commands

| Command | What it does |
|---|---|
| `just install` | Run Ansible playbook (prompts for sudo once) |
| `just update` | Pull latest from GitHub + re-run Ansible |
| `just sync` | Commit all changes with timestamp + push to GitHub |
| `just link` | Re-apply all stow symlinks |
| `just dry-run` | Preview what Ansible would change (no changes made) |
| `just status` | Git status + last sync + last backup at a glance |
| `just backup` | Backup dotfiles + project to `~/backups` via restic |

## Changing the project path

Edit one line in `~/.devrc` — startup.sh, wezterm.lua, and just backup all pick it up:

```bash
PROJECT_PATH="$HOME/your-project"
```

## Startup workflow

`startup.sh` runs at login (GNOME autostart, 8s delay) and asks:

- **Dev Mode** — Chrome (Profile 9, restore session) + WezTerm (`npm run dev-server` left pane, `claude` right pane)
- **Chill Mode** — Chrome only

Logs at `~/.local/share/startup.log`. On macOS use `startup-mac.sh` (System Settings → Login Items).

## CI

GitHub Actions runs the Ansible playbook in `--check` (dry run) mode on every push to `main`, on both `ubuntu-latest` and `macos-latest`.

## Installed tools (via Ansible)

- **Shell:** zsh, Oh My Zsh, Powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting
- **Terminal:** WezTerm, tmux + TPM, just
- **Node:** NVM, Node LTS, npm global tools (claude, vercel, typescript, pnpm, biome, opencode)
- **JS runtime:** Bun
- **Python:** uv, aider-chat
- **Editor:** Zed
- **CLI:** gh, chezmoi, stow, restic, fzf, zoxide, bat, eza, tldr
- **Clipboard:** CopyQ
- **Media:** VLC
- **Browser:** Google Chrome
- **Remote desktop:** AnyDesk
- **VPN/DNS:** Cloudflare WARP
