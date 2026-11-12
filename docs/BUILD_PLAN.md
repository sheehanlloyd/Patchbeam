# Patchbeam Build Plan

This plan follows the gates in §24 of [`PATCHBEAM_MASTER_PRD.md`](../PATCHBEAM_MASTER_PRD.md). A gate counts as done only when its build and tests have run and the evidence is recorded in [`QUALITY_REPORT.md`](QUALITY_REPORT.md).

## Gate 0: environment audit (done 2026-11-11)

These values come from commands run on the build host:

| Item | Observed |
|---|---|
| Host | `Mac16,8` (MacBook Pro 14", Apple silicon), built-in Liquid Retina XDR **with a physical notch**, 3024×1964 |
| OS / arch | macOS 26.5.1 (25F80), arm64 |
| Toolchain | Xcode 26.6 (17F113), Apple Swift 6.3.3 |
| Git | 2.51.0 (Homebrew) |
| Python | 3.14.7 (for the `broken-python` fixture; uses only the standard library) |
| ffmpeg | present (`/opt/homebrew/bin/ffmpeg`) |
| `codex` | **Broken install.** `@openai/codex` 0.93.0 is present, but `vendor/aarch64-apple-darwin/codex/codex` is missing, so `codex --version` exits with `ENOENT`. App-server cannot be used. |
| `claude` | Claude Code 2.1.252 at `~/.local/bin/claude`. `claude auth status --json` reports `loggedIn: false` for the standalone CLI. |
| GitHub | `gh` is authenticated, and `origin` points to the empty public repo `sheehanlloyd/Patchbeam` |
| Signing | No Developer ID credentials have been provided, so distribution is limited to an **unsigned development preview** |

### Provider decision (ADR-0002)

The PRD's first choice, Codex app-server, cannot run on this host because the installed binary is missing. Repairing it would change the user's global environment, which the safety rules don't allow without permission. The best supported alternative is **Claude Code headless mode** with its documented `--print --output-format stream-json --verbose` stream. Its installed protocol was probed in a scratch directory, and the real stream (`system/init`, `assistant`, `result` with `error: authentication_failed`) is checked in as a contract fixture.

- Run and stream: supported.
- Approval bridging: **not offered.** Claude Code only exposes approvals to an external host through an MCP `--permission-prompt-tool`. That is not bridged in v1, so the adapter reports `canApprove = false`, the UI has no Allow button, and denied tools show as "Approve this action in Claude Code" (see §6 Journey B).
- Scope: runs use `--tools Read,Edit,Write` (no shell), `--permission-mode acceptEdits`, `--strict-mcp-config`, `--setting-sources ""`, `--max-budget-usd`, a wall-clock timeout, and the app-owned worktree as cwd. **The host, not the agent, runs verification.**
- Live golden path: **blocked until the user runs `claude auth login`.** The unauthenticated path itself was exercised for real.

### Build-system decision (ADR-0001)

The build uses a Swift Package with three products, so it can be reproduced and checked in without a generated `.xcodeproj`:

- `PatchbeamCore`: a library with all domain logic and no UI imports (geometry, capsules, SQLite, Git, verification, agents, orchestration).
- `Patchbeam`: the SwiftUI and AppKit executable. `scripts/build.sh` wraps it in a real `Patchbeam.app` bundle (Info.plist, `LSUIElement`, icon, ad-hoc signature).
- `patchbeam-cli`: a headless driver for the fixture golden path, used by `scripts/fixture-demo.sh --headless` and CI.

## Gates

| Gate | Scope | Verification |
|---|---|---|
| 1. Native shell | NSPanel notch window, `NotchGeometryEngine`, dormant/glance/expanded/intake/review states, hotkey, menu bar extra, settings | Geometry unit tests; launch the `.app` on the notched built-in display; real screenshot |
| 2. Domain and fixture | Capsule model and state machine, SQLite (WAL, migrations), diagnostic intake with redaction, repo binding, worktrees, DemoAgent, `broken-python` fixture | red→green `unittest` proof; source checkout still red until Apply |
| 3. Real provider | Claude Code stream-json adapter, probe, auth detection, cancellation by process group | Contract tests against the captured real stream; live run when authenticated |
| 4. Review and hardening | Diff, fingerprint-bound verification, safe apply (`git apply --check` first, no reset/force), discard, crash recovery, hostile paths | Git integration tests (spaces/Unicode, dirty, symlink, detached, conflicts) |
| 5. UX | Keyboard path, VoiceOver labels, reduced motion, focus non-stealing, external-display capsule | Manual run on hardware, recorded in the quality report |
| 6. Docs, media, package | README landing page, real screenshots and recording, unsigned zip/DMG with checksum | Every README command executed |
| 7. Final audit | Clean clone → bootstrap → build → test → fixture demo | `docs/QUALITY_REPORT.md` |

## Out of scope for v1 (PRD §4.3, §5)

P1/P2 items (terminal helper, OCR intake, CI import, parallel agents) wait until every P0 gate passes. No auto-commit, push, merge, or PR creation from inside the app.
