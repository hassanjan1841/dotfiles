#!/usr/bin/env bash
# Startup workflow launcher — runs at login via GNOME autostart

# Load project path from ~/.devrc (easy to change without editing this file)
[ -f "$HOME/.devrc" ] && source "$HOME/.devrc"
PROJECT_PATH="${PROJECT_PATH:-$HOME/speaklogic-testing}"

sleep 8

CHOICE=$(zenity --list \
  --title="Choose Workflow" \
  --text="What do you want to do today?" \
  --radiolist \
  --column="" --column="Mode" \
  TRUE  "Dev Mode" \
  FALSE "Chill Mode" \
  --width=300 --height=200 2>/dev/null)

case "$CHOICE" in
  "Dev Mode")
    # Chrome — "someone" profile, restore last session
    google-chrome --profile-directory="Profile 9" --restore-last-session &

    # Terminal window 1 — tab 1: dev server, tab 2: claude
    gnome-terminal \
      --tab --title="Dev Server" -- zsh -c "cd '$PROJECT_PATH' && npm run dev-server; exec zsh" \
      --tab --title="Claude"     -- zsh -c "cd '$PROJECT_PATH' && claude; exec zsh" &

    # Terminal window 2 — claude
    gnome-terminal \
      --window --title="Claude 2" -- zsh -c "cd '$PROJECT_PATH' && claude; exec zsh" &
    ;;

  "Chill Mode")
    google-chrome --profile-directory="Profile 9" --restore-last-session &
    ;;

  *)
    # User closed the dialog — do nothing
    ;;
esac
