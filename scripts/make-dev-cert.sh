#!/bin/zsh
# Creates a self-signed "Deskpouch Dev" code signing certificate in the login keychain and points this machine's
# build at it through Signing.local.xcconfig (git-ignored).
# Why: ad-hoc signed builds get a new identity on every rebuild, so macOS forgets the Accessibility and Microphone
# grants each time. A stable certificate keeps them. macOS will show one or two Keychain dialogs; approve them.
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="Deskpouch Dev"
KEYCHAIN=~/Library/Keychains/login.keychain-db
P12_PASS=deskpouch
tmp=$(mktemp -d)
# The private key is written unencrypted while the script runs; remove it on every exit path.
trap 'rm -rf "$tmp"' EXIT

trust() {
  # Trust the certificate for code signing in the user domain (shows a password dialog).
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$1"
}

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "identity '$NAME' already exists"
elif security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  # Imported by an earlier run whose trust step was cancelled: trust it now instead of importing a duplicate.
  echo "identity '$NAME' exists but is not trusted yet"
  security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$tmp/cert.pem"
  trust "$tmp/cert.pem"
else
  cat > "$tmp/ext.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF
  # System LibreSSL and legacy PKCS#12 algorithms: the macOS importer rejects OpenSSL 3's AES/SHA-256 default.
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -days 3650 -config "$tmp/ext.cnf" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/dev.p12" -passout "pass:$P12_PASS" -name "$NAME" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES
  security import "$tmp/dev.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign -T /usr/bin/security
  trust "$tmp/cert.pem"
fi
security find-identity -v -p codesigning | grep "$NAME"
printf '// Written by scripts/make-dev-cert.sh. Not tracked.\nCODE_SIGN_IDENTITY = %s\n' "$NAME" > Signing.local.xcconfig
echo "Signing.local.xcconfig now uses '$NAME'. Rebuild with scripts/run.sh, then grant Accessibility and Microphone once."
