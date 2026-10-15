#!/usr/bin/env bash
# Installs the repository's git hooks.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ln -sf "$ROOT/scripts/pre-commit" "$ROOT/.git/hooks/pre-commit"
echo "✓ pre-commit hook installed"
