#!/usr/bin/env bash
# Installs the repository's git hooks.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_PATH="$(git -C "$ROOT" rev-parse --git-path hooks/pre-commit)"
if [[ "$HOOK_PATH" != /* ]]; then
    HOOK_PATH="$ROOT/$HOOK_PATH"
fi
mkdir -p "$(dirname "$HOOK_PATH")"
ln -sf "$ROOT/scripts/pre-commit" "$HOOK_PATH"
echo "✓ pre-commit hook installed"
