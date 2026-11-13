#!/bin/zsh
# Create a persistent, local-only code-signing identity for this app.
set -eu
umask 077
signing_name='Calendar Studio Local Development'
login_keychain="$HOME/Library/Keychains/login.keychain-db"
if /usr/bin/security find-identity -v -p codesigning "$login_keychain" | /usr/bin/grep -Fq "\"$signing_name\""; then
    echo 'Calendar Studio signing identity is already installed.'
    exit 0
fi
if /usr/bin/security find-certificate -c "$signing_name" "$login_keychain" >/dev/null 2>&1; then
    echo 'A certificate with this name exists but is not a usable signing identity. No replacement was created.' >&2
    exit 1
fi
signing_temp_dir=$(mktemp -d /private/tmp/calendar-studio-signing.XXXXXX)
trap 'rm -rf "$signing_temp_dir"' EXIT
openssl_path=$(command -v openssl)
"$openssl_path" req -x509 -newkey rsa:2048 -sha256 -nodes \
    -keyout "$signing_temp_dir/key.pem" -out "$signing_temp_dir/certificate.pem" \
    -days 3650 -subj "/CN=$signing_name/" \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=codeSigning' 2>/dev/null
# The private key is imported into the login Keychain, never into the shared project.
signing_import_password=$("$openssl_path" rand -hex 24)
export CALENDAR_STUDIO_IMPORT_PASSWORD="$signing_import_password"
"$openssl_path" pkcs12 -export -legacy \
    -inkey "$signing_temp_dir/key.pem" -in "$signing_temp_dir/certificate.pem" \
    -out "$signing_temp_dir/identity.p12" -name "$signing_name" \
    -passout env:CALENDAR_STUDIO_IMPORT_PASSWORD
/usr/bin/security import "$signing_temp_dir/identity.p12" -k "$login_keychain" \
    -P "$signing_import_password" -T /usr/bin/codesign
unset CALENDAR_STUDIO_IMPORT_PASSWORD signing_import_password
# User-level trust is limited to code signing; no system-wide or TLS trust.
/usr/bin/security add-trusted-cert -r trustRoot -p codeSign -k "$login_keychain" "$signing_temp_dir/certificate.pem"
/usr/bin/security find-identity -v -p codesigning "$login_keychain"
