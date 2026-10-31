#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=2.9.6
SHA256=52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192
DEST="Vendor/Sparkle-$VERSION"
if [[ -f "$DEST/.verified-$SHA256" && -d "$DEST/Sparkle.framework" && -x "$DEST/bin/generate_appcast" ]]; then exit 0; fi
[[ ! -e "$DEST" ]] || { echo "Neúplná závislost: $DEST. Přesuňte ji a spusťte znovu." >&2; exit 1; }
mkdir -p Vendor
TEMP_DIR="$(mktemp -d "$PWD/Vendor/.sparkle.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
  "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" \
  -o "$TEMP_DIR/sparkle.tar.xz"
echo "$SHA256  $TEMP_DIR/sparkle.tar.xz" | shasum -a 256 -c -
mkdir "$TEMP_DIR/extracted"
tar -xJf "$TEMP_DIR/sparkle.tar.xz" -C "$TEMP_DIR/extracted"
codesign --verify --deep --strict "$TEMP_DIR/extracted/Sparkle.framework"
touch "$TEMP_DIR/extracted/.verified-$SHA256"
mv "$TEMP_DIR/extracted" "$DEST"
