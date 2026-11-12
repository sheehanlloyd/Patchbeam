# Quality report

Generated from executed commands on 2026-11-12. Each line is one of three things: **Passed** (with the evidence), **Failed**, or **Not tested**. Nothing is marked passed from model prose or unit tests alone where the PRD asks for more.

## Build identity

| Item | Value |
|---|---|
| Commit audited | Clean-clone audit at `de29ea7`; published preview built from `db9efd0` (build 17) |
| Host | Mac16,8 (MacBook Pro 14", Apple silicon), built-in Liquid Retina XDR **with physical notch**, 1512×982 pt @2x |
| OS / arch | macOS 26.5.1 (25F80), arm64 |
| Toolchain | Xcode 26.6 (17F113), Apple Swift 6.3.3; CI: GitHub `macos-15` runner, Xcode 16 |
| Git / Python | 2.51.0 / 3.14.7 |
| Provider CLI | Claude Code 2.1.252, auto-updated to 2.1.322 on 2026-11-12; signed in by the user on 2026-11-12, after which live runs succeeded. Codex 0.93.0 **broken install** |
| App binary SHA-256 | `2f3bc8add6a0b1ef8af5a6ec7e710a2dd255dc8f5fae7375327357be3da9de60` (`Patchbeam.app/Contents/MacOS/Patchbeam` inside the published DMG, build 17) |
| Preview DMG SHA-256 | `f1c3fb9b7d46b7d1d1b55eafc8fbaf8f95f1ccefc599341790822485b0bd42fb`, published as pre-release [v0.1.0-preview](https://github.com/sheehanlloyd/Patchbeam/releases/tag/v0.1.0-preview). Re-downloaded from GitHub: `shasum -c` OK. |
| Signing | Ad-hoc only (`codesign --sign -`, hardened runtime). **Not** Developer ID signed, **not** notarized. `spctl --assess` → `rejected` (expected). |

## Commands and results

| Command | Result | Evidence |
|---|---|---|
| `./scripts/bootstrap.sh --check` | **Passed** | All prerequisites ✔ (clean clone, `/tmp/pb-audit.*`) |
| `./scripts/build.sh release` | **Passed** | `Built build/Release/Patchbeam.app (0.1.0 build 15, ad-hoc signed…)`; `codesign --verify --strict` ok |
| `./scripts/test.sh` | **Passed: 115/115 tests, 14 suites, 0 skipped**, ~7.5 s (114 at the clean-clone audit; +1 real-success contract test) | Clean clone, plus CI `macos-15` (run 43239917574: "Unit + integration tests" ✔) |
| `./scripts/fixture-demo.sh --headless` (fix) | **Passed** | `RESULT: PASS`: baseline exit 1 → patch exit 0; source red until apply; after apply `HEAD` unchanged, nothing staged, only `calculator.py` modified |
| `… --scenario wrongFixThenFix` | **Passed** | First attempt `reviewReadyFailed` (never green), one approved retry → verified |
| `… --scenario approval` | **Passed** | `awaitingApproval` → Allow Once runs the real command (exit 1 reproduced) → verified |
| `./scripts/check-docs.sh` | **Passed** once this file exists | Earlier CI failures were caused only by this missing report |
| `./scripts/package-dmg.sh` | **Passed** | `hdiutil verify` ok; `codesign --verify` of the app *inside* the DMG ok; `shasum -c` ok; installed copy of the build-17 DMG ran `--autodemo` → `applied` |
| CI (`.github/workflows/ci.yml`) | **Passed** for tests, demos and bundle build; docs step fixed in this commit | Run 43239917574 step log |

### Bugs found by this verification and fixed (in git history)
1. Secret-scanner regexes backtracked quadratically: a 300 KB log took **258 s** to scan. After bounding the quantifiers, it scans in 0.19 s, with a timing regression test.
2. Path canonicalization mismatch under `/private/tmp` made every GUI repair fail with "Worktree path escaped" (found only by running the real app). Fixed with `realpath`, plus a regression test.
3. Title inference preferred "FAILED (failures=1)" over the assertion line.
4. A non-terminal event emitted after `completed` violated the stream contract.
5. Lossy date encoding made reopened capsules compare unequal.
6. UI, from reviewing the app's own rendered frames: header wrapping, truncated demo badge, beam highlight leaking outside its rail, the 2D diff scroll view clipping line starts, green proof hidden below the fold.
7. DMG staging added xattrs after signing, which broke the ad-hoc signature inside the image.
8. Intermittent codesign failure when Finder/LaunchServices touched the registered app in `build/`. The bundle is now signed in a private temp dir.
9. In the first live run, the agent's full final message appeared twice (as `message` and as the `completed` summary). The completed event is now a short summary.

## Requirement verdicts (PRD §25)

### Core product
| Requirement | Verdict | Evidence / note |
|---|---|---|
| Real compiled SwiftUI/AppKit app, no web backend | **Passed** | `build/Release/Patchbeam.app`; launched many times (`--autodemo` runs) |
| Physical-notch geometry on a real notched Mac | **Passed (numeric), visual not captured** | `docs/media/geometry-evidence.log` from the live app on the built-in display: OS notch `(663, 950, 185×32)`, dormant panel `(657, 950, 197×32)`, `panelTop==screenTop:true`, `panelMidX-notchMidX=0.0`, expanded `513×518` `onScreen=true`. A desktop screenshot around the camera housing was **not** captured (no Screen Recording permission; see ADR-0003). |
| Non-notch / external display fallback and bounds | **Passed (unit), Not tested on hardware** | `GeometryTests` (external 2560×1440, short and tiny displays, unplug re-home). No external monitor was attached. |
| Keyboard, hover/click, focus, animation, accessibility | **Partially tested** | Keyboard shortcuts, VoiceOver labels and reduced-motion paths are implemented. The UI flow was exercised through `--autodemo` (model-driven). **Not tested:** pointer hover/click by a person, VoiceOver walkthrough, Increase Contrast. |
| Diagnostic paste/drop + repo selection | **Passed (logic) / Partially tested (UI)** | `DiagnosticsTests` (10), intake frames. Drag-and-drop and the NSOpenPanel weren't exercised by automation. |
| Git worktree, base commit, dirty warning | **Passed** | `GitIntegrationTests` (20), `dirtySourceIsWarnedAndUntouched` |
| One working live provider adapter | **Passed** | After `claude auth login` (2026-11-12), probe → `ready` (2.1.322). **CLI:** `patchbeam-cli run --provider claude-code … --yes --apply` on a fresh fixture: baseline exit 1 → Claude Code read 2 files and edited `calculator.py` → host check exit 0 (3/3) → applied; source `unittest` OK, `HEAD` unchanged, nothing staged; 4 turns, $0.0532, 8.7 s. **App:** `--autodemo-live` repeated it in the GUI → `applied`. Before sign-in, the probe reported `notAuthenticated` and `run --yes` failed closed with `PB-AGENT-AUTH`, creating no worktree. |
| Demo adapter separately labeled | **Passed** | Every DemoAgent event has `scripted=true`; the "Demo — no model used" badge appears in every frame |
| Events, approvals, cancellation, error paths | **Passed** | Approval allow/deny/expiry/replay, process-group cancel, transport failure, refusal, auth failure (`AgentTests`, `GoldenPathTests`) |
| Verification keeps exit code, logs, fingerprint | **Passed** | `VerificationRunnerTests` (exit 0/1, signal 9, timeout, unapproved, missing tool, escape), proof cards |
| Diff review, open in editor, safe apply, discard | **Passed (apply/discard/diff) / Not tested (open in editor)** | Apply preconditions tested. "Open in Editor" not exercised (would launch the user's editor). |
| No silent mutations, commits, pushes, bypass | **Passed** | `journeyA…` asserts HEAD unchanged and nothing staged; hooks disabled (`repositoryHooksNeverRun`, plus manual proof that a hook runs without the flag) |
| Restart/recovery and retention | **Passed** | `journeyE_restartMarksInterruptedAndPreservesWorktree`; Delete All Local History implemented |

### Verification
| Requirement | Verdict | Evidence |
|---|---|---|
| Deterministic red→green from a pristine environment | **Passed** | Clean clone + three headless scenarios + the GUI autodemo from the DMG-installed copy reached `applied` |
| No model output can forge verified state | **Passed** | `verifiedRequiresHostProofNotModelText`, `editingAfterVerificationBlocksApply`, `checkThatMutatesFilesInvalidatesProof` |
| Adversarial Git, injection, process, stale approval, crash | **Passed** | Shell-injection argv, hostile hooks, symlink escape, `../` executable, ANSI/bidi, stale approval replay, crash reconciliation |
| Build/test scripts pass on the documented toolchain | **Passed** | Local Xcode 26.6 and CI Xcode 16 |
| UI test suite and hardware manual checks | **Partially tested** | No XCUITest target (ADR-0001). GUI exercised via `--autodemo` and reviewed frame by frame. Manual hardware checklist items still open. |
| Real-provider flow | **Passed** | CLI and GUI live runs above; redacted real stream `Tests/Fixtures/claude-stream/success-2.1.322.jsonl` is a contract test |

### Shipping
| Requirement | Verdict | Evidence |
|---|---|---|
| README with authentic hero and working install instructions | **Passed** | `hero.gif` 9.2 s (960×540, 5× speed labeled), stills; Quick Start re-run from a clean clone |
| 45–90 s demo of a real start-to-finish repair | **Passed, with disclosed scope** | `Patchbeam-Demo.mp4` 53.1 s, 1920×1080 H.264. Real app window, real Git and tests, scripted agent. No desktop shown. Every frame watched in review stills. |
| Real-provider clip | **Passed** | `docs/media/Patchbeam-Agent-Run.mp4`, 38.5 s, live Claude Code 2.1.322, labeled on every frame |
| Links, paths, alt text, commands validated | **Passed** | `check-docs.sh`; every README command executed |
| DMG signed and notarized | **Not done (no credentials)** | Unsigned preview only, labeled everywhere |
| Checksums, license, changelog, security, privacy, troubleshooting | **Passed** | Files present |
| Fresh machine/user or VM install | **Partially tested** | DMG mounted, app copied to a fresh folder and run with a fresh data dir → `applied`. **Not** a new macOS user account or VM. |

## Performance (Mac16,8, release build)

| Metric | Target | Measured |
|---|---|---|
| Launch → panel visible (wall-clock, `open` to on-screen) | < 2 s | First run 632 ms; next six runs 215–227 ms (p50 ≈ 223 ms, p95 ≈ 227 ms) |
| In-process `main` → panel ordered front | — | 75–102 ms |
| Idle CPU, 5 min average (60 samples × 5 s, `ps`) | < 1 % | **0.00 %** |
| Idle memory (RSS) | < 180 MB | **46.8 MB average, 52.3 MB max** |
| Expand/collapse frame rate | 60 fps | **Not measured** (no Instruments capture). Spring ≈ 0.32 s response. The beam animates only while work executes. |

## Media

| File | Exists | Length / size | Review |
|---|---|---|---|
| `docs/media/Patchbeam-Demo.mp4` | yes | 53.1 s, 1920×1080, 1.1 MB | Sampled frames reviewed; captions come from recorded state |
| `docs/media/hero.gif` | yes | 9.2 s, 960×540, 0.5 MB | Labeled "5× speed" on every frame |
| `docs/media/0*-*.png`, `10-applied.png` | yes | panel @2x | Reviewed |
| `docs/media/geometry-evidence.log`, `autodemo.log`, `chapters.txt` | yes | text | No usernames or home paths |
| `docs/media/Patchbeam-Agent-Run.mp4` | yes | 38.5 s, 1920×1080 | Live Claude Code run in the app; stills `live-05-running.png`, `live-08-review-proof.png` reviewed |
| Desktop-context recording (panel around the camera housing) | **no** | — | Blocked: Screen Recording permission not granted (`scripts/record-desktop.sh` ready) |

## Known limitations
1. **Live provider coverage is one fixture.** Claude Code repaired the bundled fixture (CLI and GUI). It hasn't been exercised on larger real-world repositories.
2. **Claude Code approvals aren't bridged.** Denied tools are surfaced with "Approve this action in Claude Code's terminal." The agent has only Read/Edit/Write tools.
3. **Codex isn't supported** (the host install is broken).
4. **Unsigned preview.** Gatekeeper rejects the DMG app until you choose Control-click → Open. Without Developer ID credentials there's no notarized build.
5. **No XCUITest suite.** GUI coverage comes from the model-driven `--autodemo` plus frame review. Pointer, VoiceOver, Increase Contrast, full-screen/Spaces and external displays need the manual checks in [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).
6. **Media shows the app's panel, not the desktop.** Physical fit is evidenced numerically.
7. The global shortcut is fixed at ⌃⌥Space. Conflicts are detected and reported, but it can't be rebound yet.
8. One repair runs at a time (by design in v1). P1/P2 features (terminal helper, OCR, CI import, parallel agents) aren't built.

## Release-readiness verdict
**Development preview: ready for source builds and local evaluation with the offline DemoAgent.** **Not ready for a trusted public release.** That's blocked by (a) Developer ID signing and notarization, and (b) the manual hardware/accessibility checks listed above. The live provider path is now verified on the fixture.
