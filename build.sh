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
if [[ -d ".build/release/Dhun_Dhun.bundle" ]]; then
  cp -R ".build/release/Dhun_Dhun.bundle" "$APP_DIR/Contents/Resources/"
fi
if [[ -f Dhun.icns ]]; then
  cp Dhun.icns "$APP_DIR/Contents/Resources/Dhun.icns"
fi
# Prefer the stable local "Dhun Dev" identity (scripts/make-signing-cert.sh)
# so macOS permissions survive rebuilds; fall back to ad-hoc.
SIGN_IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Dhun Dev"; then
  SIGN_IDENTITY="Dhun Dev"
fi
codesign --force --sign "$SIGN_IDENTITY" "$APP_DIR"
echo "Signed with: $SIGN_IDENTITY"

echo "Built: $APP_DIR"
echo "Run:   open \"$APP_DIR\""
