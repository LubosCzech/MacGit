#!/bin/bash
# Všechny regresní sady najednou – spouští je i scripts/new-release.sh před vydáním.
# Žádná sada nic nepodepisuje, nenotarizuje ani nekontaktuje Apple.
# Obyčejné řetězce místo polí: macOS má bash 3.2, kde prázdné pole pod `set -u` spadne.
set -euo pipefail
cd "$(dirname "$0")/.."

FAILED=""
suite() {
  local name="$1"; shift
  printf '▸ %s\n' "$name"
  "$@" || FAILED="$FAILED $name"
  return 0
}

suite gitkit-tests swift test --package-path Packages/GitKit
suite app-build xcodebuild -project Revision.xcodeproj -scheme Revision -configuration Debug \
  -derivedDataPath build build -quiet
suite appcast-tests python3 -m unittest discover -s Tests -p 'test_*.py'
suite release-mode-tests bash Tests/release-mode-tests.sh

if [[ -n "$FAILED" ]]; then
  printf '\n✗ Selhalo:%s\n' "$FAILED" >&2
  exit 1
fi
printf '\n✓ Všechny sady prošly.\n'
