#!/usr/bin/env bash
# Builds Patchbeam.app (unsigned development preview, ad-hoc signed) and patchbeam-cli.
# usage: scripts/build.sh [debug|release]   → build/<Config>/Patchbeam.app
set -euo pipefail
cd "$(dirname "$0")/.."
config="${1:-release}"
case "$config" in debug) Config=Debug ;; release) Config=Release ;; *) echo "usage: $0 [debug|release]" >&2; exit 2 ;; esac
version="$(cat VERSION 2>/dev/null || echo 0.1.0)"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

swift build -c "$config" --product Patchbeam
swift build -c "$config" --product patchbeam-cli
bin="$(swift build -c "$config" --show-bin-path)"

app="build/$Config/Patchbeam.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Fixtures"
cp "$bin/Patchbeam" "$app/Contents/MacOS/Patchbeam"
cp "$bin/patchbeam-cli" "build/$Config/patchbeam-cli"
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build_number/" Resources/Info.plist > "$app/Contents/Info.plist"
cp -R Tests/Fixtures/broken-python "$app/Contents/Resources/Fixtures/broken-python"
rm -rf "$app/Contents/Resources/Fixtures/broken-python/__pycache__"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
plutil -lint "$app/Contents/Info.plist" >/dev/null

# Copied files can carry Finder/provenance xattrs, which codesign rejects.
xattr -cr "$app"

# Ad-hoc signature only (no Developer ID): lets the bundle run locally with hardened runtime.
# This is NOT notarization and does not make the app trusted by Gatekeeper on other Macs.
codesign --force --sign - --options runtime --timestamp=none "$app"
codesign --verify --strict "$app"
echo "Built $app ($version build $build_number, ad-hoc signed, unsigned preview)"
