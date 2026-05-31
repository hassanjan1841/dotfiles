#!/usr/bin/env bash
# Daily automated routine: pull dotfiles, update npm, backup, clean cache

set -euo pipefail

LOG="$HOME/.local/share/daily.log"
DOTFILES="$HOME/dotfiles"
BACKUPS="$HOME/backups"
NOTES="$HOME/notes"
PROJECT="$HOME/speaklogic-testing"

mkdir -p "$(dirname "$LOG")"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
ntfy() {
  source "$HOME/.secrets" 2>/dev/null || true
  [ -n "${NTFY_TOPIC:-}" ] && curl -s -d "$1" "https://ntfy.sh/$NTFY_TOPIC" &>/dev/null || true
}

SUMMARY=()
ERRORS=()

log "=== daily routine started ==="

# 1. Pull latest dotfiles
log "pulling dotfiles..."
if git -C "$DOTFILES" pull --rebase 2>>"$LOG"; then
  SUMMARY+=("dotfiles:ok")
else
  ERRORS+=("dotfiles:pull-failed")
fi

# 2. npm global update
log "updating global npm packages..."
if command -v npm &>/dev/null; then
  if npm update -g 2>>"$LOG"; then
    SUMMARY+=("npm:ok")
  else
    ERRORS+=("npm:failed")
  fi
fi

# 3. Restic backup
log "running restic backup..."
source "$HOME/.secrets" 2>/dev/null || true
if [ -n "${RESTIC_PASSWORD:-}" ]; then
  export RESTIC_PASSWORD
  BACKUP_PATHS=("$DOTFILES")
  [ -d "$NOTES" ]   && BACKUP_PATHS+=("$NOTES")
  if restic -r "$BACKUPS" backup "${BACKUP_PATHS[@]}" 2>>"$LOG"; then
    restic -r "$BACKUPS" forget --keep-last 10 --prune 2>>"$LOG"
    SUMMARY+=("backup:ok")
  else
    ERRORS+=("backup:failed")
  fi
else
  log "skipping backup: RESTIC_PASSWORD not set"
fi

# 4. Clean ~/.cache entries older than 7 days
log "cleaning old cache..."
find "$HOME/.cache" -maxdepth 2 -type f -mtime +7 -delete 2>/dev/null || true
SUMMARY+=("cache:cleaned")

log "=== daily routine finished ==="

if [ ${#ERRORS[@]} -eq 0 ]; then
  MSG="daily: ok — ${SUMMARY[*]}"
else
  MSG="daily: errors — ${ERRORS[*]}"
fi
ntfy "$MSG"
