#!/usr/bin/env bash
# Packages build/Release/Patchbeam.app into dist/Patchbeam-<version>-arm64[-unsigned-preview].dmg
# plus a SHA-256 checksum file. Does not sign with a Developer ID (see release.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(cat VERSION)"
app="build/Release/Patchbeam.app"
[[ -d "$app" ]] || ./scripts/build.sh release
suffix="${PATCHBEAM_DMG_SUFFIX:--unsigned-preview}"
name="Patchbeam-$version-arm64$suffix"
mkdir -p dist
stage="$(mktemp -d)"
cp -R "$app" "$stage/Patchbeam.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/READ ME FIRST.txt" <<TXT
Patchbeam $version — UNSIGNED DEVELOPMENT PREVIEW (Apple silicon, macOS 15+)

This build is ad-hoc signed only. It is not signed with a Developer ID and not notarized
by Apple, so Gatekeeper will block it on first open.

To run it: drag Patchbeam to Applications, then Control-click Patchbeam → Open → Open.
(Do not disable Gatekeeper globally.) Building from source is the recommended path:
https://github.com/sheehanlloyd/Patchbeam#build-from-source
TXT
rm -f "dist/$name.dmg"
hdiutil create -quiet -volname "Patchbeam $version" -srcfolder "$stage" -fs APFS -format UDZO "dist/$name.dmg"
rm -rf "$stage"
(cd dist && shasum -a 256 "$name.dmg" > "$name.dmg.sha256")
hdiutil verify -quiet "dist/$name.dmg"
echo "dist/$name.dmg"
cat "dist/$name.dmg.sha256"
