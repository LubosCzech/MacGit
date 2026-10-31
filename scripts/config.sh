#!/bin/bash
# Sourced by the build/release scripts from the project root.
source ./release.env
if [[ -f release.local.env ]]; then source ./release.local.env; fi
case "${RELEASE_MODE:-}" in
  adhoc|notarized) ;;
  *) echo "RELEASE_MODE musí být adhoc nebo notarized." >&2; exit 1 ;;
esac
[[ "$APP_VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || { echo "Neplatná APP_VERSION" >&2; exit 1; }
[[ "$APP_BUILD" =~ ^[1-9][0-9]*$ ]] || { echo "APP_BUILD musí být rostoucí kladné celé číslo." >&2; exit 1; }
[[ -z "${APPLE_TEAM_ID:-}" || "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "APPLE_TEAM_ID musí mít 10 znaků A-Z0-9." >&2; exit 1; }
SPARKLE_DIR="$PWD/Vendor/Sparkle-2.9.6"
UPDATE_FEED_URL=""
if [[ -n "$GITHUB_REPOSITORY" || -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  [[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Doplňte GITHUB_REPOSITORY=owner/repo" >&2; exit 1; }
  if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    [[ "$SPARKLE_PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "Doplňte 32bajtový base64 SPARKLE_PUBLIC_ED_KEY" >&2; exit 1; }
    UPDATE_FEED_URL="https://github.com/$GITHUB_REPOSITORY/releases/latest/download/appcast.xml"
  else
    echo "▸ Repozitář nastaven; aktualizace jsou vypnuté do doplnění SPARKLE_PUBLIC_ED_KEY." >&2
  fi
fi
