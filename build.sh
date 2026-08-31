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
# The shaders live here; an app without them has broken visualizers,
# so a missing bundle is a build failure, not a shrug.
if [[ ! -d ".build/release/Dhun_Dhun.bundle" ]]; then
  echo "error: .build/release/Dhun_Dhun.bundle missing — resources did not build" >&2
  exit 1
fi
cp -R ".build/release/Dhun_Dhun.bundle" "$APP_DIR/Contents/Resources/"
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
