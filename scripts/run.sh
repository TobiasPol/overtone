#!/usr/bin/env bash
# Builds a debug app bundle and launches it (quitting any running copy first).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-app.sh" debug
pkill -x Overtone 2>/dev/null || true
open "$ROOT/build/Overtone.app"
