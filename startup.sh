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

    # One ptyxis window with a tmuxinator session:
    # left pane = npm run dev-server, right pane = claude
    ptyxis -- tmuxinator start dev &

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
