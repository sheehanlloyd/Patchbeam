# Changelog

## 0.1.0 — unreleased development preview (2026-11-12)

### Added
- Native notch panel (NSPanel + SwiftUI) with dormant, glance, intake and cockpit states, driven by a tested `NotchGeometryEngine`. Floating capsule on non-notched displays.
- Diagnostic intake: paste, drop or choose a log; sanitization; secret redaction; title inference.
- Repository binding with dirty-tree and unborn-HEAD handling; app-owned Git worktrees on `patchbeam/<id>` branches.
- Host-owned verification: approved argv, no shell, exit code, logs, red-before baseline, and fingerprint-bound proof that's revoked when files change.
- Review: Activity, Git diff and Proof views; fail-closed Apply to the working tree (never commits); Discard and Keep; one bounded retry.
- Claude Code adapter (stream-json; scoped to Read/Edit/Write; approvals deferred to Claude Code) and a scripted, clearly labeled DemoAgent.
- Crash/restart reconciliation, SQLite persistence with migrations, Delete All Local History.
- `patchbeam-cli` (headless demo, provider probe, live run), build/test/package/release scripts, CI.
- Authentic demo media recorded from the running app (`scripts/record-demo.sh`), plus a live Claude Code clip (`LIVE=1`).
- Live Claude Code 2.1.322 repair verified on the fixture (CLI and GUI).

### Known limitations
See [docs/QUALITY_REPORT.md](docs/QUALITY_REPORT.md#known-limitations).
