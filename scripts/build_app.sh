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
# CLI rides inside the bundle: Bundle.main then resolves to Shiftly.app, so
# the bundled Python helpers are found without a repo checkout. Named
# shiftly-cli because the filesystem is case-insensitive and "shiftly"
# would collide with the app binary "Shiftly".
cp "ShiftlyApp/.build/$CONFIG/shiftly" "$APP/Contents/MacOS/shiftly-cli"
# Bundle the Python helpers so the app works without a repo checkout
# (a scripts/ dir at the data root still takes precedence at runtime).
cp scripts/planner.py scripts/schedule_core.py scripts/work_history.py \
   "$APP/Contents/Resources/scripts/"
# Localizations: keys are the English texts (fallback), zh-Hans is bundled.
cp -R ShiftlyApp/Localization/zh-Hans.lproj "$APP/Contents/Resources/"
# App icon (regenerate with: swift scripts/make_icon.swift + iconutil).
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Shiftly</string>
  <key>CFBundleIdentifier</key>
  <string>com.shiftly.app</string>
  <key>CFBundleName</key>
  <string>Shiftly</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleDisplayName</key>
  <string>Shiftly</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.7.0</string>
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
  <key>NSMicrophoneUsageDescription</key>
  <string>Shiftly records meeting audio into your meetings folder when you press Record.</string>
</dict>
</plist>
PLIST

# Native WidgetKit widgets: hand-built extension (no Xcode). WidgetKit
# only loads sandboxed extensions, hence the entitlement; the app group
# is the data path between the (unsandboxed) app and the widget.
APPEX="$APP/Contents/PlugIns/ShiftlyWidgets.appex"
mkdir -p "$APPEX/Contents/MacOS"
# App extensions enter through NSExtensionMain (XPC bootstrap), not a
# plain Swift main — WidgetKit then instantiates the @main WidgetBundle.
swiftc -O -parse-as-library \
  -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macos15.0 \
  -Xlinker -e -Xlinker _NSExtensionMain \
  ShiftlyApp/Widgets/ShiftlyWidgets.swift \
  -o "$APPEX/Contents/MacOS/ShiftlyWidgets"

cat > "$APPEX/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>ShiftlyWidgets</string>
  <key>CFBundleDisplayName</key>
  <string>Shiftly</string>
  <key>CFBundleIdentifier</key>
  <string>com.shiftly.app.widgets</string>
  <key>CFBundleExecutable</key>
  <string>ShiftlyWidgets</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>DTPlatformName</key>
  <string>macosx</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.7.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.widgetkit-extension</string>
  </dict>
  <key>EXAppExtensionAttributes</key>
  <dict>
    <key>EXExtensionPointIdentifier</key>
    <string>com.apple.widgetkit-extension</string>
  </dict>
</dict>
</plist>
PLIST

WIDGET_ENT="$(mktemp -t shiftly-widget-ent).plist"
cat > "$WIDGET_ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.com.shiftly.app</string>
  </array>
</dict>
</plist>
PLIST

codesign --force -s - --entitlements "$WIDGET_ENT" "$APPEX"
rm -f "$WIDGET_ENT"

codesign --force -s - "$APP"
echo "Built $APP"
