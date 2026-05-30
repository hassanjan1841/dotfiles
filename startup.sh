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

# Snap two ptyxis windows left/right using window-calls DBus extension (Wayland-native)
snap_ptyxis_windows() {
    local retries=20
    local win1 win2 json ids

    while [ $retries -gt 0 ]; do
        json=$(gdbus call --session \
          --dest org.gnome.Shell \
          --object-path /org/gnome/Shell/Extensions/Windows \
          --method org.gnome.Shell.Extensions.Windows.List 2>/dev/null \
          | sed "s/^('//; s/',)$//; s/\\\\n//g")

        mapfile -t ids < <(python3 -c "
import sys, json
wins = json.loads(sys.stdin.read())
for w in wins:
    if 'ptyxis' in (w.get('wm_class') or '').lower():
        print(w['id'])
" <<< "$json" 2>/dev/null)

        win1="${ids[0]:-}"
        win2="${ids[1]:-}"

        if [ -n "$win1" ] && [ -n "$win2" ]; then
            break
        fi
        sleep 0.5
        retries=$((retries - 1))
    done

    if [ -z "$win1" ] || [ -z "$win2" ]; then
        echo "Warning: could not find both ptyxis windows via window-calls"
        return 1
    fi

    gdbus call --session --dest org.gnome.Shell \
      --object-path /org/gnome/Shell/Extensions/Windows \
      --method org.gnome.Shell.Extensions.Windows.MoveResize \
      "uint32:$win1" "int32:0" "int32:0" "uint32:$HALF_W" "uint32:$SCREEN_H" 2>/dev/null

    gdbus call --session --dest org.gnome.Shell \
      --object-path /org/gnome/Shell/Extensions/Windows \
      --method org.gnome.Shell.Extensions.Windows.MoveResize \
      "uint32:$win2" "int32:$HALF_W" "int32:0" "uint32:$HALF_W" "uint32:$SCREEN_H" 2>/dev/null

    echo "Snapped ptyxis windows: $win1 (left) $win2 (right)"
}

case "$CHOICE" in
  "Dev Mode")
    fix_chrome_exit
    google-chrome --profile-directory="Profile 9" &

    # Window 1 — left half: dev server
    ptyxis -- zsh -ic "cd '$PROJECT_PATH' && npm run dev-server; exec zsh" &

    # Window 2 — right half: claude
    sleep 1
    ptyxis -- zsh -ic "cd '$PROJECT_PATH' && claude; exec zsh" &

    # Snap both windows via window-calls DBus (Wayland-compatible)
    snap_ptyxis_windows &

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
