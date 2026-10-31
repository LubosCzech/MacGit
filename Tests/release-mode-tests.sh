#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/release-mode.sh
CALLS=""
# Mock all external actions: these tests never sign or notarize real files.
codesign() { CALLS+="codesign $*;"; }
xcrun() { CALLS+="xcrun $*;"; }
ditto() { CALLS+="ditto $*;"; }
spctl() { CALLS+="spctl $*;"; }
hdiutil() { CALLS+="hdiutil $*;"; }
RELEASE_MODE=adhoc
REVISION_SIGN_IDENTITY='Developer ID Application: stale identity'
unset REVISION_NOTARY_PROFILE
configure_release_signing
[[ "$REVISION_SIGN_IDENTITY" == - ]]
notarize_release_app fixture.app /fixture
finish_release_dmg fixture.dmg
verify_release_dmg fixture.dmg
[[ "$CALLS" == 'hdiutil verify fixture.dmg;hdiutil verify fixture.dmg;' ]]
echo 'PASS: adhoc forces ad-hoc signing and never invokes Apple notarization'
RELEASE_MODE=notarized
if (configure_release_signing 2>/dev/null); then echo 'FAIL: missing certificate accepted'; exit 1; fi
REVISION_SIGN_IDENTITY='Developer ID Application: Fixture (TEAMONE123)'
if (configure_release_signing 2>/dev/null); then echo 'FAIL: missing profile accepted'; exit 1; fi
REVISION_NOTARY_PROFILE=fixture
unset APPLE_TEAM_ID
if (configure_release_signing 2>/dev/null); then echo 'FAIL: missing team accepted'; exit 1; fi
APPLE_TEAM_ID=TEAMTWO456
if (configure_release_signing 2>/dev/null); then echo 'FAIL: certificate from another team accepted'; exit 1; fi
APPLE_TEAM_ID=TEAMONE123
configure_release_signing
[[ "$REVISION_SIGN_IDENTITY" == *'(TEAMONE123)'* ]]
CALLS=""
notarize_release_app fixture.app /fixture
finish_release_dmg fixture.dmg
verify_release_dmg fixture.dmg
[[ "$CALLS" == *'notarytool submit /fixture/notarize.zip'* ]]
[[ "$CALLS" == *'notarytool submit fixture.dmg'* ]]
[[ "$CALLS" == *'stapler validate fixture.app'* ]]
[[ "$CALLS" == *'stapler validate fixture.dmg'* ]]
[[ "$CALLS" == *'codesign --verify --strict fixture.dmg'* ]]
echo 'PASS: notarized requires credentials, rejects a foreign team, validates app and DMG'
RELEASE_MODE=invalid
if (configure_release_signing 2>/dev/null); then echo 'FAIL: unknown mode accepted'; exit 1; fi
echo 'PASS: invalid mode rejected (no silent downgrade)'
