#!/bin/zsh
# Builds a release binary and wraps it in build/Gesture.app (needed for the camera
# permission prompt and an Accessibility identity). Signed with "Gesture Local Signing" if that
# identity exists (see make-signing-identity.sh), so permissions survive rebuilds; otherwise
# ad-hoc, which macOS treats as a new app on every build.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Gesture
BIN="$(swift build -c release --show-bin-path)/Gesture"
APP=build/Gesture.app
VERSION="${VERSION:-0.1.0}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Gesture"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.gesture.app</string>
  <key>CFBundleName</key><string>Gesture</string>
  <key>CFBundleDisplayName</key><string>Gesture</string>
  <key>CFBundleExecutable</key><string>Gesture</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key><string>Gesture tracks your hands with the camera to control the Mac. Video never leaves this computer.</string>
</dict>
</plist>
PLIST

IDENTITY="Gesture Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" --identifier local.gesture.app "$APP"
  echo "Built $APP (signed: $IDENTITY)"
else
  codesign --force --sign - --identifier local.gesture.app "$APP"
  echo "Built $APP (ad-hoc: run scripts/make-signing-identity.sh to keep permissions across rebuilds)"
fi
