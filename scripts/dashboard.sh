#!/usr/bin/env bash
# Personal dashboard — shown once per day on terminal open

DOTFILES="$HOME/dotfiles"
BACKUPS="$HOME/backups"

_ver() {
  local cmd="$1"; shift
  if command -v "$cmd" &>/dev/null; then
    echo "  $cmd: $("$@" 2>/dev/null | head -1)"
  else
    echo "  $cmd: not installed"
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  Dashboard  •  %s\n" "$(date '+%A, %B %d %Y  %H:%M')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# System
echo ""
echo "── System ───────────────────────────────────────────────"
echo "  Uptime:  $(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /')"
if [[ "$(uname)" == "Darwin" ]]; then
  CPU=$(top -l 1 | awk '/CPU usage/ {print $3}')
  MEM=$(vm_stat | awk 'BEGIN{a=0;w=0} /Pages active/{a=$3+0} /Pages wired/{w=$4+0} END{printf "%.1f GB active/wired", (a+w)*4096/1073741824}')
else
  CPU=$(top -bn1 | awk '/Cpu\(s\)/{print $2}')%
  MEM=$(free -h | awk '/^Mem/{print $3 " / " $2}')
fi
echo "  CPU:     $CPU"
echo "  Memory:  $MEM"
echo "  Disk:    $(df -h "$HOME" | awk 'NR==2{print $3 " / " $2 " (" $5 " used)"}')"

# Dotfiles
echo ""
echo "── Dotfiles ─────────────────────────────────────────────"
if [ -d "$DOTFILES" ]; then
  cd "$DOTFILES" 2>/dev/null || true
  echo "  Branch:  $(git branch --show-current 2>/dev/null)"
  echo "  Last:    $(git log -1 --format='%ar — %s' 2>/dev/null)"
  CHANGES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  [ "$CHANGES" -gt 0 ] && echo "  Status:  $CHANGES uncommitted change(s)" || echo "  Status:  clean"
fi

# Backup
echo ""
echo "── Last Backup ──────────────────────────────────────────"
if command -v restic &>/dev/null && [ -d "$BACKUPS" ]; then
  source "$HOME/.secrets" 2>/dev/null || true
  LAST=$(restic -r "$BACKUPS" snapshots --last 2>/dev/null | grep -E "^[0-9a-f]{8}" | tail -1 | awk '{print $2, $3}')
  [ -n "$LAST" ] && echo "  Last:    $LAST" || echo "  Last:    no snapshots found"
else
  echo "  Status:  restic not configured"
fi

# Tasks
echo ""
echo "── Tasks due today ──────────────────────────────────────"
if command -v task &>/dev/null; then
  COUNT=$(task due:today count 2>/dev/null || echo 0)
  if [ "$COUNT" -gt 0 ] 2>/dev/null; then
    task due:today rc.verbose=nothing 2>/dev/null | head -8
  else
    echo "  No tasks due today"
  fi
fi

# Time tracking
echo ""
echo "── Time tracked today ───────────────────────────────────"
if command -v timew &>/dev/null; then
  timew summary :day 2>/dev/null | tail -4 || echo "  No time tracked today"
else
  echo "  timewarrior not installed"
fi

# Tool versions
echo ""
echo "── Tools ────────────────────────────────────────────────"
_ver node node --version
_ver just just --version
if command -v fdfind &>/dev/null; then
  echo "  fd: $(fdfind --version 2>/dev/null | head -1)"
elif command -v fd &>/dev/null; then
  echo "  fd: $(fd --version 2>/dev/null | head -1)"
else
  echo "  fd: not installed"
fi
_ver rg rg --version
_ver claude claude --version

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
