#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source release.env
if [[ -f release.local.env ]]; then source release.local.env; fi
bash scripts/fetch-sparkle.sh
echo "Vytvořím klíč v přihlašovací Klíčence (účet $SPARKLE_KEY_ACCOUNT), existující klíč zachovám."
Vendor/Sparkle-2.9.6/bin/generate_keys --account "$SPARKLE_KEY_ACCOUNT"
echo "Veřejný klíč výše vložte do SPARKLE_PUBLIC_ED_KEY v release.env. Soukromý klíč zůstává v Klíčence."
