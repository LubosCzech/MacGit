#!/bin/bash
# Shared release signing policy; source this file, then call the functions.
configure_release_signing() {
  case "${RELEASE_MODE:-}" in
    adhoc)
      export REVISION_SIGN_IDENTITY=-
      echo "▸ Ad-hoc vydání: bez ověření vydavatele Applem a bez notarizace. Sparkle podpisy zůstávají povinné." >&2
      ;;
    notarized)
      [[ "${REVISION_SIGN_IDENTITY:-}" == 'Developer ID Application:'* ]] || { echo "Nastavte Developer ID Application certifikát." >&2; return 1; }
      [[ -n "${REVISION_NOTARY_PROFILE:-}" ]] || { echo "Nastavte REVISION_NOTARY_PROFILE." >&2; return 1; }
      # Signing with a second team would reset every granted permission again.
      [[ -n "${APPLE_TEAM_ID:-}" ]] || { echo "Nastavte APPLE_TEAM_ID v release.env." >&2; return 1; }
      [[ "$REVISION_SIGN_IDENTITY" == *"($APPLE_TEAM_ID)"* ]] || {
        echo "Certifikát nepatří týmu $APPLE_TEAM_ID: $REVISION_SIGN_IDENTITY" >&2; return 1; }
      export REVISION_SIGN_IDENTITY APPLE_TEAM_ID
      ;;
    *) echo "Neznámý režim vydání." >&2; return 1 ;;
  esac
}

notarize_release_app() {
  [[ "$RELEASE_MODE" == notarized ]] || return 0
  ditto -c -k --keepParent "$1" "$2/notarize.zip"
  xcrun notarytool submit "$2/notarize.zip" --keychain-profile "$REVISION_NOTARY_PROFILE" --wait
  xcrun stapler staple "$1"
  xcrun stapler validate "$1"
  spctl --assess --type execute --verbose=2 "$1"
}

finish_release_dmg() {
  if [[ "$RELEASE_MODE" == notarized ]]; then
    codesign --force --sign "$REVISION_SIGN_IDENTITY" --timestamp "$1"
    xcrun notarytool submit "$1" --keychain-profile "$REVISION_NOTARY_PROFILE" --wait
    xcrun stapler staple "$1"
  fi
  hdiutil verify "$1"
}

verify_release_dmg() {
  # Ed25519 verification is mandatory in release.sh, regardless of this mode.
  if [[ "$RELEASE_MODE" == notarized ]]; then
    xcrun stapler validate "$1"
    codesign --verify --strict "$1"
  fi
  hdiutil verify "$1"
}
