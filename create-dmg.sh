#!/bin/bash
# Build and package Revision using macOS tools; no additional dependencies.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_APP=true
case "${1:-}" in
  --no-build) BUILD_APP=false; shift ;;
  --help|-h)
    echo "Použití: $0 [--no-build]"
    echo "Sestaví Revision a vytvoří dist/Revision-<verze>-<architektura>.dmg."
    echo "--no-build zabalí existující build/Revision.app. Existující DMG nepřepisuje."
    exit 0 ;;
esac
if [[ $# -ne 0 ]]; then
  echo "Neznámý parametr. Použijte --help." >&2
  exit 1
fi
[[ "$(uname -s)" == Darwin ]] || { echo "Skript vyžaduje macOS." >&2; exit 1; }
if "$BUILD_APP"; then /bin/bash "${PROJECT_DIR}/build.sh"; fi

APP_PATH="${PROJECT_DIR}/build/Revision.app"
PLIST="${APP_PATH}/Contents/Info.plist"
[[ -f "$PLIST" ]] || { echo "Chybí build/Revision.app. Spusťte skript bez --no-build." >&2; exit 1; }
/usr/bin/plutil -lint "$PLIST"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
[[ "$EXECUTABLE" == Revision ]] || { echo "Neočekávaná aplikace v build/Revision.app." >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+([.][0-9]+)*$ ]] || { echo "Neplatná verze: $VERSION" >&2; exit 1; }
ARCHS="$(/usr/bin/lipo -archs "${APP_PATH}/Contents/MacOS/Revision")"
ARCH_LABEL="${ARCHS// /-}"
if [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]]; then ARCH_LABEL=universal; fi
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

DIST_DIR="${REVISION_DMG_DIR:-${PROJECT_DIR}/dist}"
mkdir -p "$DIST_DIR"
OUTPUT="${DIST_DIR}/Revision-${VERSION}-${ARCH_LABEL}.dmg"
if [[ -e "$OUTPUT" || -L "$OUTPUT" ]]; then
  echo "DMG již existuje: $OUTPUT" >&2
  echo "Před novým vytvořením ho přejmenujte nebo přesuňte." >&2
  exit 1
fi

STAGING="$(mktemp -d "${DIST_DIR}/.revision-dmg.XXXXXX")"
cleanup() {
  # Only remove the unique temporary directory created by this invocation.
  if [[ -n "${STAGING:-}" && "$STAGING" == "$DIST_DIR"/.revision-dmg.* && -d "$STAGING" ]]; then
    /bin/rm -rf "$STAGING"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "${STAGING}/contents"
/usr/bin/ditto "$APP_PATH" "${STAGING}/contents/Revision.app"
/bin/ln -s /Applications "${STAGING}/contents/Applications"
/usr/bin/codesign --verify --deep --strict "${STAGING}/contents/Revision.app"

echo "▸ Vytvářím instalační DMG…"
/usr/bin/hdiutil create -volname Revision -srcfolder "${STAGING}/contents" \
  -fs HFS+ -format UDZO "${STAGING}/Revision.dmg"
/usr/bin/hdiutil verify "${STAGING}/Revision.dmg"
# Publish only a complete, verified image, without replacing earlier output.
/bin/ln "${STAGING}/Revision.dmg" "$OUTPUT"
echo "✓ Hotovo: $OUTPUT"
echo "Instalace: otevřete DMG a přetáhněte Revision do Applications."
