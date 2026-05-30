#!/usr/bin/env bash
# Startup workflow launcher — runs at login via GNOME autostart
# Delay is handled by X-GNOME-Autostart-Delay in startup.desktop

LOG="$HOME/.local/share/startup.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"

[ -f "$HOME/.devrc" ] && source "$HOME/.devrc"
PROJECT_PATH="${PROJECT_PATH:-$HOME/speaklogic-testing}"

CHOICE=$(zenity --list \
  --title="Choose Workflow" \
  --text="What do you want to do today?" \
  --radiolist \
  --column="" --column="Mode" \
  TRUE  "Dev Mode" \
  FALSE "Chill Mode" \
  --width=300 --height=200 2>/dev/null)

echo "Choice: ${CHOICE:-cancelled}"

# Fix Chrome restore button — mark last session as clean exit
fix_chrome_exit() {
    local prefs="$HOME/.config/google-chrome/Profile 9/Preferences"
    if [ -f "$prefs" ]; then
        python3 -c "
import json
with open('$prefs') as f:
    p = json.load(f)
p.setdefault('profile', {})['exit_type'] = 'Normal'
p.setdefault('profile', {})['exited_cleanly'] = True
with open('$prefs', 'w') as f:
    json.dump(p, f)
" 2>/dev/null
    fi
}

case "$CHOICE" in
  "Dev Mode")
    fix_chrome_exit
    google-chrome --profile-directory="Profile 9" &

    # Kill any existing dev session — tmux-continuum may have restored one with
    # a stale directory. We always want a clean layout.
    tmux kill-session -t dev 2>/dev/null

    # Build the session before opening the terminal so ptyxis just attaches.
    # Left pane: dev-server  |  Right pane: claude
    tmux new-session -d -s dev -c "$PROJECT_PATH"
    tmux send-keys -t dev "npm run dev-server" Enter
    tmux split-window -h -t dev -c "$PROJECT_PATH"
    tmux send-keys -t dev "claude" Enter
    tmux select-pane -t dev:1.1

    ptyxis -- tmux attach -t dev &

    echo "Dev Mode launched"
    ;;

  "Chill Mode")
    fix_chrome_exit
    google-chrome --profile-directory="Profile 9" &
    echo "Chill Mode launched"
    ;;

  *)
    echo "Dialog cancelled — nothing launched"
    ;;
esac
