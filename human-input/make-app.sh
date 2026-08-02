#!/bin/sh
# Wraps the binary in a signed .app so it holds macOS permissions under its own
# identity instead of borrowing whichever terminal launched it. That is what lets it
# run from cron, launchd, or a double click and still be allowed to send input.
#
# The signature is ad-hoc (-s -). Good enough for a stable identity on this machine,
# but every re-sign is a new identity, so macOS will ask for Accessibility again after
# a rebuild. A real Developer ID avoids that.
set -e
cd "$(dirname "$0")"
./build.sh

APP=Human.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp human "$APP/Contents/MacOS/human"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Human</string>
  <key>CFBundleIdentifier</key><string>dev.hassanjan.human</string>
  <key>CFBundleExecutable</key><string>human</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Reads window geometry from other applications.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier dev.hassanjan.human "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/  /'

echo
echo "built $(pwd)/$APP"
echo "run it with: $(pwd)/$APP/Contents/MacOS/human check"
echo "grant Accessibility to Human.app the first time it is used."
