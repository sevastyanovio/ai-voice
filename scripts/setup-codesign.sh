#!/bin/bash
# Creates a self-signed code signing certificate "AI Voice Local".
# Once installed, build.sh will use it instead of ad-hoc signing, so
# Accessibility / Microphone / other TCC grants survive rebuilds.
#
# Run once:  bash scripts/setup-codesign.sh
set -e

IDENTITY="AI Voice Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "✓ Identity '$IDENTITY' already installed."
    security find-identity -v -p codesigning | grep "$IDENTITY"
    exit 0
fi

echo "Creating self-signed code signing cert '$IDENTITY'..."

# OpenSSL config with code signing extended key usage
cat > "$TMP/config.cnf" <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_dn
prompt             = no
x509_extensions    = v3_ext

[ req_dn ]
CN = $IDENTITY

[ v3_ext ]
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
EOF

openssl genrsa -out "$TMP/key.pem" 2048 2>/dev/null
openssl req -new -x509 -key "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -config "$TMP/config.cnf"
openssl pkcs12 -export -legacy -out "$TMP/bundle.p12" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:aivoice

echo "Importing into login keychain..."
security import "$TMP/bundle.p12" -k "$KEYCHAIN" -P aivoice -T /usr/bin/codesign -A

echo "Trusting cert for code signing..."
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" 2>&1 || true

# Allow codesign to use the key without prompting
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo ""
echo "✓ Done. Identity installed:"
security find-identity -v -p codesigning | grep "$IDENTITY" || echo "  (not visible yet — try 'security find-identity -v -p codesigning')"
echo ""
echo "Now rebuild: bash build.sh"
