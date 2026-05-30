#!/usr/bin/env bash
# Startup workflow launcher — runs at login via GNOME autostart
# Delay is handled by X-GNOME-Autostart-Delay in startup.desktop

LOG="$HOME/.local/share/startup.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"

[ -f "$HOME/.devrc" ] && source "$HOME/.devrc"
PROJECT_PATH="${PROJECT_PATH:-$HOME/speaklogic-testing}"

# Get screen dimensions
SCREEN_W=$(xrandr | grep " connected" | grep -oP '\d+x\d+' | head -1 | cut -dx -f1)
SCREEN_H=$(xrandr | grep " connected" | grep -oP '\d+x\d+' | head -1 | cut -dx -f2)
SCREEN_W=${SCREEN_W:-1920}
SCREEN_H=${SCREEN_H:-1080}
HALF_W=$((SCREEN_W / 2))

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

# Snap a window by partial title to a given position and size
# Usage: snap_window "title" x y width height
snap_window() {
    local title="$1" x="$2" y="$3" w="$4" h="$5"
    local retries=10
    while [ $retries -gt 0 ]; do
        if wmctrl -r "$title" -e "0,$x,$y,$w,$h" 2>/dev/null; then
            return 0
        fi
        sleep 0.5
        retries=$((retries - 1))
    done
    echo "Warning: could not snap window '$title'"
}

case "$CHOICE" in
  "Dev Mode")
    fix_chrome_exit

    # wmctrl cannot see Wayland-native windows (ptyxis is GTK4/Wayland).
    # Instead: launch each window, wait for it to focus, then trigger GNOME's
    # tiling shortcut via xdotool. Chrome launches last so it won't steal focus.

    # Window 1 — left half: dev server
    ptyxis -- zsh -ic "cd '$PROJECT_PATH' && npm run dev-server; exec zsh" &
    sleep 2
    DISPLAY=:0 xdotool key super+Left

    # Window 2 — right half: claude
    ptyxis -- zsh -ic "cd '$PROJECT_PATH' && claude; exec zsh" &
    sleep 2
    DISPLAY=:0 xdotool key super+Right

    # Launch Chrome last so it doesn't steal focus during tiling
    google-chrome --profile-directory="Profile 9" &

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
