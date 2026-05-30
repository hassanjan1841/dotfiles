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
# If called from bootstrap.sh, sudo is already cached — use --become instead
install:
    #!/usr/bin/env bash
    if sudo -n true 2>/dev/null; then
        ansible-playbook {{dotfiles}}/setup.yml --become
    else
        ansible-playbook {{dotfiles}}/setup.yml --ask-become-pass
    fi

# Pull latest dotfiles from GitHub then re-run the playbook
update:
    cd {{dotfiles}} && git pull
    #!/usr/bin/env bash
    if sudo -n true 2>/dev/null; then
        ansible-playbook {{dotfiles}}/setup.yml --become
    else
        ansible-playbook {{dotfiles}}/setup.yml --ask-become-pass
    fi

# Commit all changes and push to GitHub (uses current date+time as message)
sync:
    cd {{dotfiles}} && git add -A
    cd {{dotfiles}} && git diff --cached --quiet || git commit -m "sync: $(date '+%Y-%m-%d %H:%M:%S')"
    cd {{dotfiles}} && git push

# Re-apply all stow symlinks
link:
    cd {{dotfiles}} && stow -v --restow bash git zsh dev tmux p10k aliases taskwarrior
    cd {{dotfiles}} && stow -v --no-folding --restow claude
    stow -v --restow --target="{{env_var('HOME')}}/.config/zed"        --dir={{dotfiles}} zed
    stow -v --restow --target="{{env_var('HOME')}}/.config/autostart"  --dir={{dotfiles}} autostart
    cd {{dotfiles}} && stow -v --restow wezterm

# Preview what Ansible would change without applying anything
dry-run:
    ansible-playbook {{dotfiles}}/setup.yml --check --diff -i localhost, --connection local

# Show dotfiles git status, last sync, and last backup at a glance
status:
    #!/usr/bin/env bash
    echo "── Dotfiles git status ──────────────────────────"
    cd {{dotfiles}} && git status -s && echo "Branch: $(git branch --show-current) | $(git log -1 --format='Last commit: %ar — %s')"
    echo ""
    echo "── Last sync ────────────────────────────────────"
    cd {{dotfiles}} && git log -1 --format="%ci  %s"
    echo ""
    echo "── Last backup ──────────────────────────────────"
    if command -v restic &>/dev/null && [ -d {{backups}} ]; then
        source "$HOME/.secrets" 2>/dev/null || true
        restic -r {{backups}} snapshots --last 2>/dev/null | tail -3 || echo "No backups found"
    else
        echo "Restic not configured yet"
    fi

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

# Show task list (taskwarrior)
tasks:
    task list

# Profile zsh startup time and show zprof breakdown
zsh-profile:
    #!/usr/bin/env bash
    printf "── Startup time (3 runs) ──────────────────────────\n"
    for i in 1 2 3; do { time zsh -i -c exit; } 2>&1 | grep real; done
    printf "\n── zprof breakdown ────────────────────────────────\n"
    ZPROF=1 zsh -i -c exit
