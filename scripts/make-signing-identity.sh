#!/bin/zsh
# Creates a self-signed code-signing certificate, "Gesture Local Signing", in the login keychain.
#
# Ad-hoc signatures change on every build, and macOS ties Accessibility and Camera permission to
# the signature, so every rebuild looks like a new app. Signed with a stable certificate, the
# app keeps its permissions across rebuilds. scripts/bundle.sh uses this identity when present.
#
# Remove it later with: security delete-identity -c "Gesture Local Signing"
set -euo pipefail

NAME="Gesture Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists."
    exit 0
fi

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
cat > "$DIR/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$DIR/cert.cnf" \
    -keyout "$DIR/key.pem" -out "$DIR/cert.pem" 2>/dev/null
PASS=$(openssl rand -hex 16)
# OpenSSL 3 needs -legacy for a PKCS#12 that the macOS keychain can read; LibreSSL doesn't know it.
openssl pkcs12 -export -legacy -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -name "$NAME" \
    -out "$DIR/id.p12" -passout "pass:$PASS" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -name "$NAME" \
    -out "$DIR/id.p12" -passout "pass:$PASS"
security import "$DIR/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign

echo "Created \"$NAME\". Run 'make app', then grant Accessibility one last time."
