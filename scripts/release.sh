#!/usr/bin/env bash
# Signs, notarizes and staples a release ONLY when real credentials are present:
#   DEVELOPER_ID_APPLICATION  e.g. "Developer ID Application: Name (TEAMID)" (in the login keychain)
#   NOTARY_PROFILE            a `xcrun notarytool store-credentials` keychain profile name
# Without them it builds the clearly labeled unsigned preview and says so. Never bypasses Gatekeeper.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh release
if [[ -z "${DEVELOPER_ID_APPLICATION:-}" || -z "${NOTARY_PROFILE:-}" ]]; then
  echo "No Developer ID / notary credentials: producing an UNSIGNED PREVIEW, not a trusted release."
  exec ./scripts/package-dmg.sh
fi
app="build/Release/Patchbeam.app"
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$app"
codesign --verify --strict --verbose=2 "$app"
PATCHBEAM_DMG_SUFFIX="" ./scripts/package-dmg.sh
dmg="dist/Patchbeam-$(cat VERSION)-arm64.dmg"
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"
(cd dist && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
echo "Signed, notarized and stapled: $dmg"
