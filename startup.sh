#!/usr/bin/env bash
# Startup workflow launcher — runs at login via GNOME autostart
# Delay is handled by X-GNOME-Autostart-Delay in startup.desktop

LOG="$HOME/.local/share/startup.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"

[ -f "$HOME/.devrc" ] && source "$HOME/.devrc"
PROJECT_PATH="${PROJECT_PATH:-$HOME/speaklogic-testing}"

# Get screen width for positioning terminals side by side
SCREEN_W=$(xrandr | grep " connected" | grep -oP '\d+x\d+' | head -1 | cut -dx -f1)
SCREEN_W=${SCREEN_W:-1920}
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

case "$CHOICE" in
  "Dev Mode")
    # Chrome — "Continue where you left off" is set in profile settings
    google-chrome --profile-directory="Profile 9" &

    # Terminal window 1 — LEFT side: tab 1: dev server, tab 2: claude
    # zsh -i loads full zshrc so NVM PATH and claude are available
    gnome-terminal \
      --geometry=120x35+0+0 \
      --tab --title="Dev Server" -- zsh -ic "cd '$PROJECT_PATH' && npm run dev-server; exec zsh" \
      --tab --title="Claude"     -- zsh -ic "cd '$PROJECT_PATH' && claude; exec zsh" &

    # Terminal window 2 — RIGHT side: claude
    gnome-terminal \
      --geometry=120x35+${HALF_W}+0 \
      --window --title="Claude 2" -- zsh -ic "cd '$PROJECT_PATH' && claude; exec zsh" &

    echo "Dev Mode launched"
    ;;

  "Chill Mode")
    google-chrome --profile-directory="Profile 9" &
    echo "Chill Mode launched"
    ;;

  *)
    echo "Dialog cancelled — nothing launched"
    ;;
esac
