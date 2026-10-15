#!/usr/bin/env bash
# CI only: imports the Developer ID Application certificate from secrets into a temporary
# keychain and writes `identity=<sha1>` to $GITHUB_OUTPUT. Without the secret it does nothing,
# and the release falls back to ad-hoc signing.
#   P12_BASE64    base64 of the exported .p12 (certificate + private key)
#   P12_PASSWORD  the .p12 export password
set -euo pipefail
if [[ -z "${P12_BASE64:-}" ]]; then
  echo "No Developer ID certificate configured; this release will be ad-hoc signed."
  exit 0
fi

work="${RUNNER_TEMP:?}/signing"
mkdir -p "$work"
keychain="$work/signing.keychain-db"
keychain_password="$(uuidgen)"

printf '%s' "$P12_BASE64" | base64 --decode > "$work/cert.p12"
# Apple's intermediate, in case the runner image lacks it.
curl -fsSL -o "$work/DeveloperIDG2CA.cer" https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer

security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/DeveloperIDG2CA.cer" -k "$keychain" -T /usr/bin/codesign || true
security import "$work/cert.p12" -k "$keychain" -P "${P12_PASSWORD:?}" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" > /dev/null
# shellcheck disable=SC2046
security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
rm -f "$work/cert.p12"

identity="$(security find-identity -v -p codesigning "$keychain" | awk '/Developer ID Application/ { print $2; exit }')"
if [[ -z "$identity" ]]; then
  echo "error: the certificate is not a Developer ID Application identity" >&2
  exit 1
fi
echo "Imported Developer ID Application identity."
echo "identity=$identity" >> "${GITHUB_OUTPUT:?}"
