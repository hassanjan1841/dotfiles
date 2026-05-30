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

case "$CHOICE" in
  "Dev Mode")
    google-chrome --profile-directory="Profile 9" --restore-last-session &
    gnome-terminal \
      --tab --title="Dev Server" -- zsh -c "cd '$PROJECT_PATH' && npm run dev-server; exec zsh" \
      --tab --title="Claude"     -- zsh -c "cd '$PROJECT_PATH' && claude; exec zsh" &
    gnome-terminal \
      --window --title="Claude 2" -- zsh -c "cd '$PROJECT_PATH' && claude; exec zsh" &
    echo "Dev Mode launched"
    ;;
  "Chill Mode")
    google-chrome --profile-directory="Profile 9" --restore-last-session &
    echo "Chill Mode launched"
    ;;
  *)
    echo "Dialog cancelled — nothing launched"
    ;;
esac
