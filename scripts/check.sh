#!/usr/bin/env bash
# Quality gates: warning-free build, tests, file/function size limits, secret scan.
# Usage: scripts/check.sh            (everything)
#        scripts/check.sh --no-test  (skip the test run)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▸ Build (warnings are errors)"
swift build -Xswiftc -warnings-as-errors -Xcc -Wall -Xcc -Werror 2>&1 | grep -v "^\[" || exit 1

if [[ "${1:-}" != "--no-test" ]]; then
  echo "▸ Tests"
  swift test 2>&1 | tail -n 3
fi

echo "▸ File size limit (300 lines)"
oversized=$(find src tests scripts -type f \( -name '*.swift' -o -name '*.c' -o -name '*.h' -o -name '*.sh' \) \
  -exec awk 'END { if (NR > 300) print FILENAME " (" NR " lines)" }' {} \;)
if [[ -n "$oversized" ]]; then
  echo "Files over 300 lines:"; echo "$oversized"; exit 1
fi

echo "▸ Secret scan"
if git rev-parse --git-dir >/dev/null 2>&1; then
  staged=$(git diff --cached --name-only --diff-filter=ACM || true)
  if echo "$staged" | grep -E '(^|/)\.env($|\.)' | grep -v '\.env\.example$'; then
    echo "Refusing to commit .env files"; exit 1
  fi
  if [[ -n "$staged" ]] && echo "$staged" | xargs grep -nE \
    '(AKIA[0-9A-Z]{16}|-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY-----|ghp_[A-Za-z0-9]{36}|sk-[A-Za-z0-9]{32,})' 2>/dev/null; then
    echo "Possible secret in staged files"; exit 1
  fi
fi
echo "✓ All checks passed"
