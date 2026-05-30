# dotfiles

Personal dotfiles for Ubuntu and macOS, managed with [GNU Stow](https://www.gnu.org/software/stow/) and [chezmoi](https://www.chezmoi.io/).

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

## Bootstrap a new machine

### Step 1 — Install Ansible

**Ubuntu:**
```bash
sudo apt install ansible
```
**macOS:**
```bash
brew install ansible
```

### Step 2 — Run the playbook

```bash
git clone https://github.com/hassanjan1841/dotfiles.git ~/dotfiles
ansible-playbook ~/dotfiles/setup.yml --ask-become-pass
```

`--ask-become-pass` prompts **once** for your sudo password at the start.
Ansible uses it for all tasks that need `sudo` (apt installs, adding package repos).
Tasks that don't need sudo (npm, bun, nvm, etc.) run as your normal user.

> On macOS most tasks use Homebrew and don't need sudo at all, so the flag is optional there.

### Step 3 — Add your secrets

```bash
cp ~/dotfiles/.secrets.example ~/.secrets   # if you add one
# or create manually:
nano ~/.secrets
# paste: export TAVILY_API_KEY="your-new-key"
```

### Step 4 — Install Tmux plugins

Open tmux and press `Ctrl+A` then `I` to install all TPM plugins.

### Step 5 — Install Zed themes

Open Zed → `Ctrl+Shift+P` → `zed: install extension` → search for your theme.
Any custom theme JSON files you save to `~/.config/zed/themes/` are auto-synced via dotfiles.

## Changing the project path

Edit one line in `~/.devrc` — both `startup.sh` and tmuxinator pick it up:

```bash
PROJECT_PATH="$HOME/your-project"
```

## Startup workflow

`startup.sh` runs at login (GNOME autostart) and asks:

- **Dev Mode** — Chrome (Profile 9, restore last session) + terminal window 1 (`npm run dev-server` + `claude`) + terminal window 2 (`claude`)
- **Chill Mode** — Chrome only

On macOS use `startup-mac.sh` (add it to System Settings → Login Items).

## tmuxinator

```bash
tmuxinator start workspace
```

Window 1: `npm run dev-server` | Window 2: `claude`

## Installed tools (via Ansible)

- **Shell:** zsh, Oh My Zsh, Powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting
- **Terminal:** tmux + TPM, tmuxinator
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
