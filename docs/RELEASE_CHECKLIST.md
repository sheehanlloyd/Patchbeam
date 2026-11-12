# Release checklist

Mark an item only with evidence (a command's output, a file, or a CI run link). Current status lives in [QUALITY_REPORT.md](QUALITY_REPORT.md).

## Every release
- [ ] `./scripts/bootstrap.sh --check` passes on the release machine
- [ ] `./scripts/test.sh` passes (record the count)
- [ ] `./scripts/fixture-demo.sh --headless` passes for `fix`, `wrongFixThenFix`, `approval`
- [ ] CI is green on the release commit
- [ ] `./scripts/record-demo.sh` re-recorded; the MP4 was watched end to end; stills reviewed
- [ ] `./scripts/check-docs.sh` passes; README commands re-run verbatim
- [ ] `CHANGELOG.md` and `VERSION` updated

## Trusted public release (blocked until credentials exist)
- [ ] Developer ID Application certificate in the keychain (`DEVELOPER_ID_APPLICATION`)
- [ ] `xcrun notarytool store-credentials` profile (`NOTARY_PROFILE`)
- [ ] `./scripts/release.sh` → `codesign --verify`, `notarytool … --wait` accepted, `stapler validate`, `spctl --assess` accepted
- [ ] SHA-256 published next to the DMG

## Unsigned preview (current path)
- [ ] `./scripts/release.sh` without credentials → `dist/Patchbeam-<v>-arm64-unsigned-preview.dmg` + `.sha256`
- [ ] Release notes say **unsigned, not notarized**, and give Control-click → Open instructions (never “disable Gatekeeper”)

## Hardware and environment checks (manual)
- [ ] Notched MacBook (Air and/or Pro): dormant island flush with the camera housing, nothing under the cutout
- [ ] External non-notched display: floating capsule below the menu bar; unplugging while expanded re-homes
- [ ] Full-screen app and Spaces: panel visibility as documented; Hide toggle works
- [ ] VoiceOver walkthrough: open, start, stop, review, apply, deny
- [ ] Reduce Motion and Increase Contrast enabled
- [ ] Clean macOS user account or VM: install from DMG, first launch, onboarding, demo
- [ ] Live Claude Code run on the fixture (`patchbeam-cli run … --yes`) after `claude auth login`
- [ ] Optional desktop recording: grant Screen Recording to your terminal, then run `./scripts/record-desktop.sh`
