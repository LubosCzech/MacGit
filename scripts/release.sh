#!/bin/bash
# Prepare a verified local release, upload a draft, then explicitly publish it.
set -euo pipefail
cd "$(dirname "$0")/.."
usage() {
  echo "Použití: bash scripts/release.sh prepare [--first-release] | upload | publish"
  echo "prepare: universal build, DMG a podepsaný appcast (RELEASE_MODE=adhoc|notarized)"
  echo "upload: nahraje ověřené soubory do nového GitHub draftu (vyžaduje existující tag)"
  echo "publish: ověří draft a zveřejní jej jako Latest"
}
[[ "${1:-}" != --help && "${1:-}" != -h ]] || { usage; exit 0; }
ACTION="${1:-}"
[[ "$ACTION" == prepare || "$ACTION" == upload || "$ACTION" == publish ]] || { usage; exit 1; }
shift
FIRST=false
if [[ "$ACTION" == prepare && "${1:-}" == --first-release ]]; then FIRST=true; shift; fi
[[ $# == 0 ]] || { usage; exit 1; }
source scripts/config.sh
source scripts/release-mode.sh
[[ -n "$UPDATE_FEED_URL" ]] || { echo "Nejprve nastavte repozitář a veřejný EdDSA klíč v release.env." >&2; exit 1; }
if [[ "$ACTION" != prepare ]]; then
  command -v gh >/dev/null || { echo "Pro upload/publish nainstalujte GitHub CLI (gh) a spusťte gh auth login; prepare přihlášení nepotřebuje." >&2; exit 1; }
fi
# Anonymous HTTPS reads also prove that users can access the update repository.
public_api() { curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "https://api.github.com/repos/$GITHUB_REPOSITORY$1"; }
[[ "$(public_api '' | python3 -c 'import json,sys; print(json.load(sys.stdin)["private"])')" == False ]] || { echo "Aktualizace vyžadují veřejný repozitář." >&2; exit 1; }
has_stable_release() {
  public_api '/releases/latest' >/dev/null 2>"$WORK/latest-error" && return 0
  # Only a confirmed 404 is treated as no release, never a connection/API error.
  local status
  status="$(curl --silent --show-error --location --proto '=https' --tlsv1.2 -o "$WORK/latest.json" -w '%{http_code}' "https://api.github.com/repos/$GITHUB_REPOSITORY/releases/latest")" || return 2
  [[ "$status" == 404 ]] && return 1
  [[ "$status" == 200 ]] && return 0
  echo "Nelze ověřit poslední vydání (HTTP $status)." >&2
  return 2
}
bash scripts/fetch-sparkle.sh
PUBLIC_KEY="$("$SPARKLE_DIR/bin/generate_keys" --account "$SPARKLE_KEY_ACCOUNT" -p)"
[[ "$PUBLIC_KEY" == "$SPARKLE_PUBLIC_ED_KEY" ]] || { echo "Podpisový klíč v Klíčence nesouhlasí s release.env." >&2; exit 1; }
TAG="v$APP_VERSION"
OUTPUT="$PWD/dist/releases/$TAG"
DMG_NAME="Revision-$APP_VERSION-universal.dmg"
PREFIX="https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/revision-release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

check_previous() {
  if "$FIRST"; then
    local result=0
    has_stable_release || result=$?
    [[ "$result" == 1 ]] || {
      echo "Repozitář již má stabilní vydání; nepoužívejte --first-release." >&2; exit 1;
    }
  else
    curl --fail --location --proto '=https' --tlsv1.2 "$UPDATE_FEED_URL" -o "$WORK/previous.xml"
    "$SPARKLE_DIR/bin/sign_update" --account "$SPARKLE_KEY_ACCOUNT" --verify "$WORK/previous.xml"
    # All Revision Sparkle builds use positive integer build numbers.
    local previous
    previous="$(xmllint --xpath 'string(/rss/channel/item[1]/*[local-name()="version"])' "$WORK/previous.xml")"
    [[ "$previous" =~ ^[1-9][0-9]*$ && "$APP_BUILD" -gt "$previous" ]] || {
      echo "APP_BUILD musí být vyšší než aktuální vydání ($previous)." >&2; exit 1;
    }
  fi
}

verify_local() {
  [[ -f "$OUTPUT/.ready" ]] || { echo "Nejprve spusťte prepare." >&2; exit 1; }
  [[ "$(< "$OUTPUT/release-mode.txt")" == "$RELEASE_MODE" ]] || { echo "Režim připraveného vydání neodpovídá konfiguraci." >&2; exit 1; }
  (cd "$OUTPUT" && shasum -a 256 -c SHA256SUMS)
  "$SPARKLE_DIR/bin/sign_update" --account "$SPARKLE_KEY_ACCOUNT" --verify "$OUTPUT/appcast.xml"
  local signature
  signature="$(python3 scripts/validate-appcast.py "$OUTPUT/appcast.xml" "$OUTPUT/$DMG_NAME" "$APP_BUILD" "$APP_VERSION" "$PREFIX")"
  "$SPARKLE_DIR/bin/sign_update" --account "$SPARKLE_KEY_ACCOUNT" --verify "$OUTPUT/$DMG_NAME" "$signature"
  verify_release_dmg "$OUTPUT/$DMG_NAME"
}

case "$ACTION" in
prepare)
  configure_release_signing
  [[ -s RELEASE_NOTES.md ]] || { echo "Vyplňte RELEASE_NOTES.md." >&2; exit 1; }
  [[ ! -e "$OUTPUT" ]] || { echo "$OUTPUT již existuje. Použijte novou verzi nebo neúplný výstup přesuňte." >&2; exit 1; }
  check_previous
  # Tag existence is checked by upload (--verify-tag); prepare has no remote writes.
  mkdir -p "$OUTPUT"
  REVISION_RELEASE_BUILD=1 REVISION_ARCHS="arm64 x86_64" bash build.sh
  notarize_release_app build/Revision.app "$WORK"
  REVISION_DMG_DIR="$OUTPUT" bash create-dmg.sh --no-build
  finish_release_dmg "$OUTPUT/$DMG_NAME"
  cp RELEASE_NOTES.md "$OUTPUT/${DMG_NAME%.dmg}.md"
  cp RELEASE_NOTES.md "$OUTPUT/RELEASE_NOTES.md"
  if [[ "$RELEASE_MODE" == adhoc ]]; then
    printf '\nToto vydání není podepsané Apple Developer ID ani notarizované. macOS může při první instalaci požadovat ruční povolení. Aktualizace a appcast jsou podepsané klíčem Sparkle.\n' >> "$OUTPUT/${DMG_NAME%.dmg}.md"
  fi
  # Preserve earlier signed entries (their download URLs continue pointing to old releases).
  if [[ -f "$WORK/previous.xml" ]]; then cp "$WORK/previous.xml" "$OUTPUT/appcast.xml"; fi
  "$SPARKLE_DIR/bin/generate_appcast" --account "$SPARKLE_KEY_ACCOUNT" \
    --download-url-prefix "$PREFIX" --embed-release-notes --maximum-deltas 0 \
    -o "$OUTPUT/appcast.xml" "$OUTPUT"
  printf '%s\n' "$RELEASE_MODE" > "$OUTPUT/release-mode.txt"
  (cd "$OUTPUT" && shasum -a 256 "$DMG_NAME" appcast.xml RELEASE_NOTES.md release-mode.txt > SHA256SUMS)
  touch "$OUTPUT/.ready"
  verify_local
  echo "✓ Připraveno: $OUTPUT. Další krok: bash scripts/release.sh upload"
  ;;
upload)
  verify_local
  gh release create "$TAG" --repo "$GITHUB_REPOSITORY" --verify-tag --draft \
    --title "Revision $APP_VERSION" --notes-file "$OUTPUT/RELEASE_NOTES.md" \
    "$OUTPUT/$DMG_NAME" "$OUTPUT/appcast.xml" "$OUTPUT/SHA256SUMS" "$OUTPUT/RELEASE_NOTES.md" "$OUTPUT/release-mode.txt"
  echo "✓ Draft nahrán. Po kontrole: bash scripts/release.sh publish"
  ;;
publish)
  verify_local
  [[ "$(gh release view "$TAG" --repo "$GITHUB_REPOSITORY" --json isDraft --jq .isDraft)" == true ]] || { echo "Očekáván nepublikovaný draft." >&2; exit 1; }
  gh release download "$TAG" --repo "$GITHUB_REPOSITORY" --dir "$WORK/download" \
    --pattern "$DMG_NAME" --pattern appcast.xml --pattern SHA256SUMS --pattern RELEASE_NOTES.md --pattern release-mode.txt
  for file in "$DMG_NAME" appcast.xml SHA256SUMS RELEASE_NOTES.md release-mode.txt; do
    cmp "$OUTPUT/$file" "$WORK/download/$file"
  done
  # A first release has no previous appcast; otherwise reject publishing an older build.
  result=0
  has_stable_release || result=$?
  if [[ "$result" == 0 ]]; then check_previous; elif [[ "$result" != 1 ]]; then exit 1; fi
  gh release edit "$TAG" --repo "$GITHUB_REPOSITORY" --draft=false --prerelease=false
  # GitHub drží příznak "latest" odděleně a při zrušení draftu jej v témže
  # volání neuplatní. Bez samostatného nastavení by latest/download/ ukazovalo
  # dál na předchozí vydání a Sparkle by tuhle verzi nikdy nenabídl.
  gh release edit "$TAG" --repo "$GITHUB_REPOSITORY" --latest
  # Příznak se v API neprojeví okamžitě, proto se na něj chvíli čeká.
  for attempt in $(seq 1 12); do
    LATEST_TAG="$(public_api '/releases/latest' | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
    if [[ "$LATEST_TAG" == "$TAG" ]]; then break; fi
    [[ "$attempt" != 12 ]] || { echo "GitHub ani po minutě neoznačil $TAG jako latest, vrací $LATEST_TAG." >&2; exit 1; }
    sleep 5
  done
  # Adresa latest/download/ zůstává chvíli v cache CDN, proto se na shodu čeká.
  for attempt in $(seq 1 12); do
    curl --fail --silent --location --proto '=https' --tlsv1.2 "$UPDATE_FEED_URL" -o "$WORK/published.xml" || true
    if cmp -s "$OUTPUT/appcast.xml" "$WORK/published.xml"; then break; fi
    [[ "$attempt" != 12 ]] || { echo "Zveřejněný appcast se ani po třech minutách neshoduje s podepsaným." >&2; exit 1; }
    sleep 15
  done
  cmp "$OUTPUT/appcast.xml" "$WORK/published.xml"
  echo "✓ Zveřejněno a ověřeno: https://github.com/$GITHUB_REPOSITORY/releases/tag/$TAG"
  ;;
esac
