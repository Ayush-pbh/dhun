#!/bin/zsh
# Creates a local self-signed code-signing certificate ("Dhun Dev") and trusts
# it for code signing. With a stable certificate, Dhun's signature no longer
# changes on every rebuild — so macOS permissions (Screen & System Audio
# Recording, Automation) finally stick.
#
# Run this yourself; macOS will ask for your login password once to record
# the trust setting.
set -euo pipefail

WORKDIR="$(mktemp -d)"
cd "$WORKDIR"

openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=Dhun Dev" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"

openssl pkcs12 -export -out dhun.p12 -inkey key.pem -in cert.pem -passout pass:dhun-signing

security import dhun.p12 \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -P dhun-signing \
  -T /usr/bin/codesign

# Trust the certificate for code signing — this is the step that asks for
# your password.
security add-trusted-cert -p codeSign \
  -k "$HOME/Library/Keychains/login.keychain-db" cert.pem

rm -rf "$WORKDIR"

echo ""
echo "Done. Signing identity available:"
security find-identity -v -p codesigning | grep "Dhun Dev" || {
  echo "…not visible yet — if the list is empty, re-run this script."
}
echo ""
echo "Now rebuild the app:  cd ~/Projects/Dhun && ./build.sh && open build/Dhun.app"
echo "macOS will ask for the screen-recording permission ONE final time —"
echo "after that it survives every rebuild."
