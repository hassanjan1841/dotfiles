# Dotfiles management commands
# Usage: just <command>
# Install just: https://github.com/casey/just

dotfiles := env_var("HOME") + "/dotfiles"
project  := env_var("HOME") + "/speaklogic-testing"
notes    := env_var("HOME") + "/notes"
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
    #!/usr/bin/env bash
    source "$HOME/.secrets" 2>/dev/null || true
    cd {{dotfiles}} && git pull
    STATUS=0
    if sudo -n true 2>/dev/null; then
        ansible-playbook {{dotfiles}}/setup.yml --become || STATUS=$?
    else
        ansible-playbook {{dotfiles}}/setup.yml --ask-become-pass || STATUS=$?
    fi
    if [ -n "${NTFY_TOPIC:-}" ]; then
        if [ "$STATUS" -eq 0 ]; then
            curl -s -d "dotfiles update: success" "https://ntfy.sh/$NTFY_TOPIC" &>/dev/null || true
        else
            curl -s -d "dotfiles update: FAILED" "https://ntfy.sh/$NTFY_TOPIC" &>/dev/null || true
        fi
    fi
    exit "$STATUS"

# Commit all changes and push to GitHub (uses current date+time as message)
sync:
    #!/usr/bin/env bash
    source "$HOME/.secrets" 2>/dev/null || true
    cd {{dotfiles}} && git add -A
    cd {{dotfiles}} && git diff --cached --quiet || git commit -m "sync: $(date '+%Y-%m-%d %H:%M:%S')"
    if cd {{dotfiles}} && git push; then
        [ -n "${NTFY_TOPIC:-}" ] && curl -s -d "dotfiles sync: success" "https://ntfy.sh/$NTFY_TOPIC" &>/dev/null || true
    else
        [ -n "${NTFY_TOPIC:-}" ] && curl -s -d "dotfiles sync: FAILED" "https://ntfy.sh/$NTFY_TOPIC" &>/dev/null || true
        exit 1
    fi

# Re-apply all stow symlinks
link:
    cd {{dotfiles}} && stow -v --restow bash git zsh dev p10k aliases
    cd {{dotfiles}} && stow -v --no-folding --restow taskwarrior
    cd {{dotfiles}} && stow -v --no-folding --restow claude
    cd {{dotfiles}} && stow -v --no-folding --restow notes
    stow -v --restow --target="{{env_var('HOME')}}/.config/zed"        --dir={{dotfiles}} zed
    stow -v --restow --target="{{env_var('HOME')}}/.config/autostart"  --dir={{dotfiles}} autostart
    cd {{dotfiles}} && stow -v --restow wezterm
    cd {{dotfiles}} && stow -v --restow startup

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

# Backup ~/dotfiles, ~/project, and ~/notes to ~/backups using restic
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
    BACKUP_PATHS=({{dotfiles}})
    [ -d "{{project}}" ] && BACKUP_PATHS+=("{{project}}")
    [ -d "{{notes}}" ]   && BACKUP_PATHS+=("{{notes}}")
    if restic -r {{backups}} backup "${BACKUP_PATHS[@]}" --verbose; then
        restic -r {{backups}} forget --keep-last 10 --prune
        [ -n "${NTFY_TOPIC:-}" ] && curl -s -d "restic backup: success" "https://ntfy.sh/$NTFY_TOPIC" &>/dev/null || true
    else
        [ -n "${NTFY_TOPIC:-}" ] && curl -s -d "restic backup: FAILED" "https://ntfy.sh/$NTFY_TOPIC" &>/dev/null || true
        exit 1
    fi

# Show personal dashboard
dashboard:
    @bash {{dotfiles}}/scripts/dashboard.sh

# Print all WezTerm key bindings
keys:
    @printf "── WezTerm Key Bindings ────────────────────────────\n"
    @printf "  Ctrl+Shift+|       Horizontal split (left/right)\n"
    @printf "  Ctrl+Alt+-         Vertical split (top/bottom)\n"
    @printf "  Ctrl+Shift+h/l/k/j Navigate panes (left/right/up/down)\n"
    @printf "  Ctrl+Shift+z       Zoom pane toggle\n"
    @printf "  Ctrl+Shift+r       Resize mode (arrow keys, Esc to exit)\n"
    @printf "  Ctrl+Shift+t       New tab\n"
    @printf "  Ctrl+Shift+w       Close pane\n"
    @printf "  Ctrl+1..5          Switch tab\n"
    @printf "  Ctrl+Shift+n/p     Next/prev workspace\n"
    @printf "  Ctrl+Shift+\$       Workspace picker\n"
    @printf "  Ctrl+Shift+q       Close workspace\n"
    @printf "  Ctrl+Shift+Alt+q   Quit WezTerm\n"
    @printf "  Shift+F2           Rename workspace\n"
    @printf "  F2                 Rename tab\n"
    @printf "  Ctrl+Shift+Space   Quick select\n"
    @printf "  Ctrl+Shift+f       Search\n"
    @printf "  Ctrl+Shift+c/v     Copy/paste\n"
    @printf "  Ctrl+Shift+↑/↓     Jump between prompts\n"
    @printf "────────────────────────────────────────────────────\n"

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
