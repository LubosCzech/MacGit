#!/bin/bash
set -euo pipefail
APP_PATH="${1:?App path required}"
IDENTITY="${REVISION_SIGN_IDENTITY:--}"
ENTITLEMENTS="$(cd "$(dirname "$0")/.." && pwd)/MacGit/MacGit.entitlements"
FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ "$IDENTITY" == - ]]; then
  # Do not enable hardened runtime/library validation for ad-hoc local builds.
  codesign --force --sign - "$FRAMEWORK"
  codesign --force --sign - "$APP_PATH"
else
  [[ "$IDENTITY" == 'Developer ID Application:'* ]] || { echo "Vyžadován Developer ID Application certifikát." >&2; exit 1; }
  codesign --force --sign "$IDENTITY" --options runtime --timestamp --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$FRAMEWORK/Versions/B/Autoupdate"
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$FRAMEWORK/Versions/B/Updater.app"
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$FRAMEWORK"
  codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS" "$APP_PATH"
  # The identity string is a label; this reads the team out of the signature.
  if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    SIGNED_TEAM="$(codesign -dv "$APP_PATH" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    [[ "$SIGNED_TEAM" == "$APPLE_TEAM_ID" ]] || {
      echo "Podepsáno týmem '${SIGNED_TEAM:-žádný}', očekáván $APPLE_TEAM_ID." >&2; exit 1; }
  fi
fi
codesign --verify --deep --strict "$APP_PATH"
