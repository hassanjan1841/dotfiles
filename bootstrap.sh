#!/usr/bin/env bash
# Run once on a fresh machine — handles everything before just/ansible exist
# Ubuntu:  bash <(curl -fsSL https://raw.githubusercontent.com/hassanjan1841/dotfiles/main/bootstrap.sh)
# macOS:   bash <(curl -fsSL https://raw.githubusercontent.com/hassanjan1841/dotfiles/main/bootstrap.sh)

set -e

DOTFILES="$HOME/dotfiles"
REPO="https://github.com/hassanjan1841/dotfiles.git"

# ── Ask for sudo password once upfront ────────────────────────────────────────
echo "==> Enter sudo password once (used for all install steps)..."
sudo -v
while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &

# ── Detect OS ─────────────────────────────────────────────────────────────────
OS="$(uname -s)"

if [ "$OS" = "Linux" ]; then
    echo "==> Installing git, ansible, curl..."
    sudo apt update -qq
    sudo apt install -y git ansible curl

    echo "==> Installing just..."
    curl -fsSL https://just.systems/install.sh | sudo bash -s -- --to /usr/local/bin

elif [ "$OS" = "Darwin" ]; then
    if ! command -v brew &>/dev/null; then
        echo "==> Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    echo "==> Installing git, ansible, just..."
    brew install git ansible just
fi

# ── Clone dotfiles ─────────────────────────────────────────────────────────────
if [ -d "$DOTFILES/.git" ]; then
    echo "==> Dotfiles already cloned — pulling latest..."
    cd "$DOTFILES" && git pull
else
    echo "==> Cloning dotfiles..."
    git clone "$REPO" "$DOTFILES"
fi

# ── Run Ansible playbook ───────────────────────────────────────────────────────
echo "==> Running Ansible playbook..."
just --justfile "$DOTFILES/Justfile" install

# ── Apply stow symlinks ────────────────────────────────────────────────────────
echo "==> Applying stow symlinks..."
just --justfile "$DOTFILES/Justfile" link

# ── Secrets reminder ───────────────────────────────────────────────────────────
if [ ! -f "$HOME/.secrets" ]; then
    echo ""
    echo "  ┌─────────────────────────────────────────────┐"
    echo "  │  One manual step remaining: create ~/.secrets │"
    echo "  │                                               │"
    echo "  │  nano ~/.secrets                              │"
    echo "  │  export TAVILY_API_KEY=\"your-key\"             │"
    echo "  │  export RESTIC_PASSWORD=\"your-backup-pass\"    │"
    echo "  └─────────────────────────────────────────────┘"
fi

echo ""
echo "==> Bootstrap complete!"
echo "    - Open tmux and press Ctrl+A then I to install plugins"
echo "    - Reboot to trigger the startup dialog"
