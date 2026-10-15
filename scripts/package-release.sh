#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel), ad-hoc signed Overtone.app and zips it for a
# GitHub release / Homebrew cask.
# Usage: scripts/package-release.sh 1.2.0
# Output: build/Overtone-1.2.0.zip and build/Overtone-1.2.0.zip.sha256
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:?usage: scripts/package-release.sh <version>}"
ZIP="build/Overtone-$VERSION.zip"

UNIVERSAL=1 VERSION="$VERSION" CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}" scripts/build-app.sh release
lipo -archs build/Overtone.app/Contents/MacOS/Overtone

rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --sequesterRsrc --keepParent build/Overtone.app "$ZIP"
shasum -a 256 "$ZIP" | awk '{print $1}' > "$ZIP.sha256"
echo "✓ $ZIP"
echo "  sha256 $(cat "$ZIP.sha256")"
