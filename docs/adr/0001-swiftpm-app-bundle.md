# ADR-0001: Build with Swift Package Manager and assemble the .app with a script

**Status:** accepted · 2026-11-11

## Context
The PRD allows a checked-in `.xcodeproj` *or* a reproducibly generated project. No project generator (XcodeGen/Tuist) is installed on the build host, and installing one would change the developer's global environment.

## Decision
`Package.swift` defines three products: `PatchbeamCore` (all domain logic, no UI imports), `Patchbeam` (the SwiftUI and AppKit executable) and `patchbeam-cli` (a headless driver). `scripts/build.sh` copies the executable, `Resources/Info.plist` (`LSUIElement`) and the bundled fixture into `build/<Config>/Patchbeam.app`, then ad-hoc signs it with the hardened runtime.

## Consequences
- `swift build` and `swift test` work in CI and from Terminal with nothing extra installed.
- There's no XCUITest target. GUI behavior is exercised by `--autodemo`, which drives the real `AppModel` and records frames, plus manual hardware checks (see QUALITY_REPORT).
- Opening `Package.swift` in Xcode works for editing and debugging.
