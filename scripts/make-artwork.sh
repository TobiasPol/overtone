#!/usr/bin/env bash
# Regenerates the app icon and README artwork from the LogoMark shape in the app's source.
#   resources/AppIcon.icns, docs/images/logo.png, docs/images/menubar.png
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift build
.build/debug/Overtone --render-artwork "$WORK"
iconutil -c icns "$WORK/AppIcon.iconset" -o resources/AppIcon.icns
mkdir -p docs/images
cp "$WORK/logo.png" "$WORK/menubar.png" docs/images/
echo "✓ Updated resources/AppIcon.icns and docs/images/"
