#!/bin/bash
# Build a double-clickable Shiftly.app into dist/ (ad-hoc signed, local use).
#   scripts/build_app.sh            release build
#   scripts/build_app.sh --debug    debug build
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
if [[ "${1:-}" == "--debug" ]]; then
  CONFIG=debug
fi

(cd ShiftlyApp && swift build -c "$CONFIG")

APP=dist/Shiftly.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/scripts"

cp "ShiftlyApp/.build/$CONFIG/ShiftlyApp" "$APP/Contents/MacOS/Shiftly"
# Bundle the Python helpers so the app works without a repo checkout
# (a scripts/ dir at the data root still takes precedence at runtime).
cp scripts/planner.py scripts/schedule_core.py scripts/work_history.py \
   "$APP/Contents/Resources/scripts/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Shiftly</string>
  <key>CFBundleIdentifier</key>
  <string>com.shiftly.app</string>
  <key>CFBundleName</key>
  <string>Shiftly</string>
  <key>CFBundleDisplayName</key>
  <string>Shiftly</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.3.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Shiftly keeps your Shifts calendar in sync with your work schedule: it creates shift events and reads back changes you make in Calendar.</string>
  <key>NSCalendarsUsageDescription</key>
  <string>Shiftly keeps your Shifts calendar in sync with your work schedule.</string>
</dict>
</plist>
PLIST

codesign --force -s - "$APP"
echo "Built $APP"
