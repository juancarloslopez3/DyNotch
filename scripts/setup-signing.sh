#!/bin/zsh
# One-time: creates a self-signed code-signing certificate "DyNotch Local Signing" in your login
# keychain and trusts it for code signing. Signing every build with it keeps the same designated
# requirement, so macOS keeps the Accessibility / Full Disk Access / camera grants across rebuilds.
# Safe to re-run: it only does the steps still missing.
set -euo pipefail
NAME="DyNotch Local Signing"
KC=~/Library/Keychains/login.keychain-db
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

if [[ -n "$(security find-identity -v -p codesigning | grep "\"$NAME\"" || true)" ]]; then
    echo "Already set up."; exit 0
fi

if [[ -z "$(security find-identity -p codesigning | grep "\"$NAME\"" || true)" ]]; then
    cat > "$T/c.cnf" <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
EOF
    # System LibreSSL: Homebrew's OpenSSL 3 writes a .p12 that `security import` rejects.
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/k.pem" -out "$T/c.pem" -days 3650 -config "$T/c.cnf" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$T/k.pem" -in "$T/c.pem" -out "$T/c.p12" -passout pass:dyn -name "$NAME"
    security import "$T/c.p12" -k "$KC" -P dyn -T /usr/bin/codesign
fi

# Without trust, codesign signs but Xcode and launchd refuse to run the app ("not codesigned").
security find-certificate -c "$NAME" -p "$KC" > "$T/trust.pem"
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$T/trust.pem"
echo "Done. Run in Xcode, allow DyNotch in Privacy one last time, and it sticks."
