#!/bin/sh
# Dhun installer — https://github.com/Ayush-pbh/dhun
#
#   curl -fsSL https://raw.githubusercontent.com/Ayush-pbh/dhun/main/install.sh | sh
#
# Downloads the latest release and installs it into /Applications. Unlike a
# browser, curl doesn't stamp macOS's quarantine flag on what it downloads,
# so the app opens right away — no Gatekeeper dialog, no settings to change.
set -eu

REPO="Ayush-pbh/dhun"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Finding the latest Dhun release…"
ZIP_URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | cut -d'"' -f4)"
if [ -z "$ZIP_URL" ]; then
  echo "Could not find a release download. Grab it manually:" >&2
  echo "  https://github.com/$REPO/releases/latest" >&2
  exit 1
fi

echo "Downloading $ZIP_URL…"
curl -fL --progress-bar "$ZIP_URL" -o "$TMP/Dhun.zip"
ditto -xk "$TMP/Dhun.zip" "$TMP"

DEST="/Applications"
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

# Replace any existing copy. If Dhun is running it keeps running from the
# old inode; the next launch uses the new version.
rm -rf "$DEST/Dhun.app"
mv "$TMP/Dhun.app" "$DEST/Dhun.app"

echo "Installed to $DEST/Dhun.app — launching."
open "$DEST/Dhun.app"
