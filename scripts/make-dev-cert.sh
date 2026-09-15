#!/bin/zsh
# Creates a self-signed "Deskpouch Dev" code signing certificate in the login keychain and points the build at it.
# Why: ad-hoc signed builds get a new identity on every rebuild, so macOS forgets the Accessibility and Microphone
# grants each time. A stable certificate keeps them. macOS will show one or two Keychain dialogs; approve them.
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="Deskpouch Dev"
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "identity '$NAME' already exists"
else
  tmp=$(mktemp -d)
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
  /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/dev.p12" -passout pass:deskpouch -name "$NAME" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES
  security import "$tmp/dev.p12" -k ~/Library/Keychains/login.keychain-db -P deskpouch -T /usr/bin/codesign -T /usr/bin/security
  # Trust it for code signing in the user domain (shows a password dialog).
  security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db "$tmp/cert.pem"
  rm -rf "$tmp"
fi
security find-identity -v -p codesigning | grep "$NAME"
sed -i '' "s/^CODE_SIGN_IDENTITY = .*/CODE_SIGN_IDENTITY = $NAME/" Signing.xcconfig
echo "Signing.xcconfig now uses '$NAME'. Rebuild with scripts/run.sh, then grant Accessibility and Microphone once."
