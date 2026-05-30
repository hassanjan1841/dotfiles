# Dotfiles management commands
# Usage: just <command>
# Install just: https://github.com/casey/just

dotfiles := env_var("HOME") + "/dotfiles"
project  := env_var("HOME") + "/speaklogic-testing"
backups  := env_var("HOME") + "/backups"

# Show available commands
default:
    @just --list

# Run the full Ansible playbook (will prompt for sudo password once)
install:
    ansible-playbook {{dotfiles}}/setup.yml --ask-become-pass

# Pull latest dotfiles from GitHub then re-run the playbook
update:
    cd {{dotfiles}} && git pull
    ansible-playbook {{dotfiles}}/setup.yml --ask-become-pass

# Commit all changes and push to GitHub (uses current date+time as message)
sync:
    cd {{dotfiles}} && git add -A
    cd {{dotfiles}} && git diff --cached --quiet || git commit -m "sync: $(date '+%Y-%m-%d %H:%M:%S')"
    cd {{dotfiles}} && git push

# Re-apply all stow symlinks
link:
    cd {{dotfiles}} && stow -v --restow bash git zsh dev tmux p10k
    stow -v --restow --target="{{env_var('HOME')}}/.config/tmuxinator" --dir={{dotfiles}} tmuxinator
    stow -v --restow --target="{{env_var('HOME')}}/.config/zed"        --dir={{dotfiles}} zed
    stow -v --restow --target="{{env_var('HOME')}}/.config/autostart"  --dir={{dotfiles}} autostart

# Backup ~/dotfiles and ~/project to ~/backups using restic
# Requires: RESTIC_PASSWORD set in ~/.secrets and restic installed
backup:
    #!/usr/bin/env bash
    source "$HOME/.secrets" 2>/dev/null || true
    if [ -z "$RESTIC_PASSWORD" ]; then
        echo "Error: RESTIC_PASSWORD not set in ~/.secrets"
        exit 1
    fi
    export RESTIC_PASSWORD
    if ! restic -r {{backups}} snapshots &>/dev/null; then
        echo "Initialising restic repo at {{backups}}..."
        restic -r {{backups}} init
    fi
    restic -r {{backups}} backup {{dotfiles}} {{project}} --verbose
    restic -r {{backups}} forget --keep-last 10 --prune
