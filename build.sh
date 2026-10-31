#!/bin/bash
# Sestaví Revision.app pro vydání: universal (Apple Silicon + Intel), Release konfigurace,
# verze a adresa aktualizací z release.env. Výsledek: build/Revision.app.
# Pro běžný vývoj stačí Xcode nebo xcodebuild (viz README).
set -euo pipefail

cd "$(dirname "$0")"
source scripts/config.sh
if [[ "${REVISION_RELEASE_BUILD:-0}" == 1 ]]; then
  source scripts/release-mode.sh
  configure_release_signing
fi
bash scripts/fetch-sparkle.sh
command -v xcodegen >/dev/null || { echo "Chybí xcodegen (brew install xcodegen)." >&2; exit 1; }
xcodegen generate --quiet

APP_DIR="build/Revision.app"
DERIVED="build/ReleaseDerivedData"
rm -rf "$APP_DIR" "$DERIVED"
mkdir -p build

echo "▸ Kompiluji Revision ${APP_VERSION} (${APP_BUILD}) pro ${REVISION_ARCHS:-$(uname -m)}…"
xcodebuild -project Revision.xcodeproj -scheme Revision -configuration Release \
  -derivedDataPath "$DERIVED" \
  ARCHS="${REVISION_ARCHS:-$(uname -m)}" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$APP_VERSION" CURRENT_PROJECT_VERSION="$APP_BUILD" \
  REVISION_FEED_URL="$UPDATE_FEED_URL" REVISION_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build -quiet

ditto "$DERIVED/Build/Products/Release/Revision.app" "$APP_DIR"
cp "$SPARKLE_DIR/LICENSE" "$APP_DIR/Contents/Resources/Sparkle-LICENSE.txt"
plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
# Podpis až nakonec: ad-hoc pro lokální build, Developer ID pro vydání (sign-app.sh).
bash scripts/sign-app.sh "$APP_DIR"
echo "✓ Hotovo: ${APP_DIR}"
echo "  Spustit: open \"${APP_DIR}\""
