#!/bin/bash
# Makes the "Fjord Dev" code-signing certificate once, on the owner's Mac: a self-signed certificate valid for ten years,
# imported with its private key into the login keychain (only codesign may use the key without asking), its .p12 kept in
# ~/.fjord-signing (readable by you only) with the .p12's password in the login keychain, and both uploaded as the
# repository secrets SIGNING_CERT_P12 and SIGNING_CERT_PASSWORD that release.yml signs with. It stops if a "Fjord Dev"
# identity or the .p12 already exists, so it never replaces a certificate apps already trust.
set -euo pipefail
umask 077
NAME="Fjord Dev"
REPO="0xpolarzero/fjord"
DIR="$HOME/.fjord-signing"
P12="$DIR/fjord-dev.p12"
SERVICE="Fjord Dev signing certificate (.p12 password)"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "A \"$NAME\" identity is already in your keychain: nothing to do." >&2; exit 1
fi
[ -e "$P12" ] && { echo "$P12 already exists: nothing to do." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Sign in to gh first (gh auth login)." >&2; exit 1; }

mkdir -p "$DIR"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')
# -legacy: macOS's security tool can't read OpenSSL 3's default .p12 encryption.
openssl pkcs12 -export -legacy -name "$NAME" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$P12" -passout "pass:$PASSWORD"

security add-generic-password -a fjord-dev-p12 -s "$SERVICE" -w "$PASSWORD" -U
security import "$P12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
echo "Imported \"$NAME\" into your login keychain; its .p12 is $P12."

base64 -i "$P12" | gh secret set SIGNING_CERT_P12 --repo "$REPO"
printf '%s' "$PASSWORD" | gh secret set SIGNING_CERT_PASSWORD --repo "$REPO"
echo "Set SIGNING_CERT_P12 and SIGNING_CERT_PASSWORD on $REPO."

security find-identity -p codesigning | grep "\"$NAME\""
echo "Done. The .p12's password is in your login keychain under \"$SERVICE\"."
echo "Keep $P12 safe (back it up): apps signed with it refuse releases signed with any other certificate."
