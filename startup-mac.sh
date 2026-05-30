#!/usr/bin/env bash
# Startup workflow launcher — macOS version (Login Items)

[ -f "$HOME/.devrc" ] && source "$HOME/.devrc"
PROJECT_PATH="${PROJECT_PATH:-$HOME/speaklogic-testing}"

sleep 8

CHOICE=$(osascript <<EOF
button returned of (display dialog "What do you want to do today?" \
  buttons {"Chill Mode", "Dev Mode"} \
  default button "Dev Mode" \
  with title "Choose Workflow")
EOF
)

case "$CHOICE" in
  "Dev Mode")
    # Open Chrome with the "someone" profile, restore last session
    open -a "Google Chrome" --args --profile-directory="Profile 9" --restore-last-session

    # Window 1 — tab 1: dev server, tab 2: claude
    osascript <<EOF
tell application "Terminal"
  activate
  do script "cd '$PROJECT_PATH' && npm run dev-server"
  tell application "System Events" to keystroke "t" using command down
  do script "cd '$PROJECT_PATH' && claude" in tab 2 of front window
end tell
EOF

    # Window 2 — claude
    osascript <<EOF
tell application "Terminal"
  activate
  do script "cd '$PROJECT_PATH' && claude"
end tell
EOF
    ;;

  "Chill Mode")
    open -a "Google Chrome" --args --profile-directory="Profile 9" --restore-last-session
    ;;
esac
