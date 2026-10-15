#!/usr/bin/env bash
# Notarizes a Developer ID signed app with Apple, staples the ticket and rebuilds its zip.
#
# Credentials (one of):
#   NOTARY_KEYCHAIN_PROFILE            profile saved with `xcrun notarytool store-credentials` (local use)
#   NOTARY_KEY_BASE64, NOTARY_KEY_ID,  App Store Connect API key (base64 of the .p8), its key ID
#   NOTARY_ISSUER_ID                   and issuer ID (CI)
#
# Usage: scripts/notarize.sh build/Overtone.app build/Overtone-1.2.0.zip
set -euo pipefail
APP="${1:?usage: scripts/notarize.sh <app> <zip>}"
ZIP="${2:?missing zip path}"

auth=()
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  auth=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${NOTARY_KEY_BASE64:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
  key_file="$(mktemp -d)/AuthKey.p8"
  trap 'rm -rf "$(dirname "$key_file")"' EXIT
  printf '%s' "$NOTARY_KEY_BASE64" | base64 --decode > "$key_file"
  auth=(--key "$key_file" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  echo "error: no notarization credentials (see scripts/notarize.sh)" >&2
  exit 1
fi

echo "▸ Submitting $ZIP for notarization (this usually takes a few minutes)"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
result="$(xcrun notarytool submit "$ZIP" "${auth[@]}" --wait --timeout 45m --output-format json)"
status="$(printf '%s' "$result" | plutil -extract status raw -o - -)"
submission="$(printf '%s' "$result" | plutil -extract id raw -o - -)"
if [[ "$status" != "Accepted" ]]; then
  echo "error: notarization finished with status '$status'" >&2
  xcrun notarytool log "$submission" "${auth[@]}" >&2 || true
  exit 1
fi

echo "▸ Stapling ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

# Re-zip so the published archive contains the stapled app (works offline on first launch).
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "✓ Notarized and stapled ($submission)"
