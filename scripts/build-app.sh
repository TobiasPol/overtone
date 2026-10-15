#!/usr/bin/env bash
# Builds build/Overtone.app. Usage: scripts/build-app.sh [release|debug]
# Optional settings come from .env (see .env.example).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Variables already set in the environment win over .env
# (e.g. CODESIGN_IDENTITY=... or VERSION=1.2.0 scripts/build-app.sh).
# shellcheck source=lib/env.sh
source scripts/lib/env.sh

CONFIG="${1:-release}"
APP_NAME="Overtone"
BUNDLE_ID="${BUNDLE_ID:-com.tobiaspol.overtone}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "▸ Compiling ($CONFIG)"
swift build -c "$CONFIG" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)"

APP="build/$APP_NAME.app"
echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
  resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [[ -f resources/AppIcon.icns ]]; then
  cp resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ Signing with identity: $SIGN_IDENTITY"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp \
    --entitlements resources/Overtone.entitlements --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
echo "✓ Built $ROOT/$APP"
