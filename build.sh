#!/bin/zsh
# Builds the release binary and assembles Dhun.app.
# The bundle matters: macOS attributes the Spotify automation permission
# to the app's bundle identifier, so run the .app rather than `swift run`.
set -euo pipefail
cd "${0:a:h}"

swift build -c release

APP_DIR="build/Dhun.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/Dhun" "$APP_DIR/Contents/MacOS/Dhun"
cp Info.plist "$APP_DIR/Contents/Info.plist"
if [[ -f Dhun.icns ]]; then
  cp Dhun.icns "$APP_DIR/Contents/Resources/Dhun.icns"
fi
codesign --force --sign - "$APP_DIR"

echo "Built: $APP_DIR"
echo "Run:   open \"$APP_DIR\""
