#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) Overtone.app and zips it for a GitHub release /
# Homebrew cask.
#
# Signing: CODESIGN_IDENTITY (default "-" = ad hoc). With a Developer ID identity plus
# notarization credentials (see scripts/notarize.sh), the app is also notarized and stapled.
#
# Usage:  scripts/package-release.sh 1.2.0
# Output: build/Overtone-1.2.0.zip, build/Overtone-1.2.0.zip.sha256
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=lib/env.sh
source scripts/lib/env.sh

VERSION="${1:?usage: scripts/package-release.sh <version>}"
ZIP="build/Overtone-$VERSION.zip"
IDENTITY="${CODESIGN_IDENTITY:--}"

UNIVERSAL=1 VERSION="$VERSION" CODESIGN_IDENTITY="$IDENTITY" scripts/build-app.sh release
lipo -archs build/Overtone.app/Contents/MacOS/Overtone

rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --sequesterRsrc --keepParent build/Overtone.app "$ZIP"

has_notary_credentials() {
  [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]] ||
    [[ -n "${NOTARY_KEY_BASE64:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]
}

if [[ "$IDENTITY" != "-" ]] && has_notary_credentials; then
  scripts/notarize.sh build/Overtone.app "$ZIP"
elif [[ "$IDENTITY" != "-" ]]; then
  echo "warning: signed but not notarized (no notarization credentials); Gatekeeper will still block it" >&2
else
  echo "Ad-hoc build: skipping notarization"
fi

shasum -a 256 "$ZIP" | awk '{print $1}' > "$ZIP.sha256"
echo "✓ $ZIP"
echo "  sha256 $(cat "$ZIP.sha256")"
