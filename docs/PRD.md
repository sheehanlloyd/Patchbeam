# PATCHBEAM
## Product Requirements Document + Autonomous Build Specification

**Tagline:** *From broken to verified, without breaking your flow.*  
**Category:** Native macOS developer tool / agentic coding companion / notch-native mission control  
**Document version:** 1.0 • 11 November 2026  
**Status:** Implementation-ready product specification; research-informed concept, not a claim that the app has been built  
**Working product name:** **Patchbeam** (provisional; conduct domain, repository, App Store, and trademark clearance before public launch)  
**Primary release target:** Apple-silicon MacBook Air and MacBook Pro with the physical display notch; macOS 15+  
**Secondary surface:** Graceful floating top-center capsule on external/non-notched displays  
**Primary distribution:** GitHub Releases, signed/notarized DMG when credentials are available; local source build always documented  
**Default philosophy:** Local-first, composable with existing coding agents, explicit consent, observable verification, reversible changes.

---

# 0. The instruction that supersedes feature enthusiasm

Build a **working, end-to-end native Mac application**, not a design prototype, website mockup, Electron dashboard, static video, or AI-chat wrapper. Deliver source, fixtures, unit/integration/UI tests, a genuinely installable artifact when the host and signing credentials permit it, reproducible build instructions, and authentic recordings of the app operating on a demo repository. No fake success states, hardcoded sample screenshots passed off as live, placeholder buttons, unsupported security guarantees, or invented compatibility claims.

The product's core achievement is **one reliable golden path**: developer supplies a failing test or error → Patchbeam associates it with a repository → starts a scoped agent in an isolated Git worktree → displays actual progress → executes an approved verification command → shows real test evidence and the resulting Git diff → developer explicitly applies or opens the patch. Build that path completely before adjacent features. If a secondary adapter or flourish threatens quality, cut it rather than the golden path.

**Safety invariant:** Nothing silently commits, pushes, merges, deletes user work, approves a dangerous tool request, captures a screen, uploads a repository, or runs arbitrary shell commands outside a disclosed, approved context. An isolated worktree is **not** a security sandbox. Label those boundaries honestly.

# 1. Executive summary

Patchbeam gives Mac developers a small, beautiful, persistent **repair cockpit in the notch**. Existing notch products elegantly display music, calendars, files, agent sessions, usage, and permission requests. Patchbeam is intentionally narrower and deeper: it turns *diagnostic evidence* into a **reviewable, verifiably tested patch**. Instead of merely showing that an agent is thinking, it tells the developer **what failed, what changed, what tests prove the result, and what action still needs human approval**.

The core unit is a **Patch Capsule**: a local record connecting (1) the original diagnostic signal, (2) repository and Git base commit, (3) agent run and its permissions, (4) resulting files and diff, (5) verification results and logs, and (6) human disposition. Capsules persist across restarts and provide a concise proof trail. They are not merely chat transcripts.

**Positioning sentence:** *Patchbeam is the notch-native control surface that converts developer failures into isolated AI repair attempts and keeps the proof in sight.*

**North-star user moment:** A failing `pytest` (or `npm test`) appears. Developer copies the traceback and taps a hotkey or drags a `.log` file into the notch. Patchbeam proposes the matched repo and a narrowly-scoped fix. The notch animates through *Diagnosing → Editing → Verifying → Review ready*. Expand to see a 3-file diff, a red-to-green test report, and **Open in Editor / Apply Patch / Discard**. Nothing touched the active working tree until explicit approval.

**Do not build:** another all-purpose AI chat client; media player; clipboard spy; generalized computer-use agent; replacement IDE; remote collaboration SaaS; or unbounded autonomous terminal.

# 2. Market and competitor research (as of 11 Nov 2026)

This is not a fresh market category. The differentiation must be honest and observable.

| Product | Verified/publicly described capability | Gap Patchbeam intentionally targets |
|---|---|---|
| **NotchNook Classic / Pro** | Classic: media, calendar, notes, file tray. Pro: Claude Code/Codex session following, approvals and replies, terminal, clipboard, other widgets. | Patchbeam centers **diagnostic intake → isolated worktree fix → verification evidence → human-controlled apply**, not a generalized notch workspace. |
| **Boring Notch** | Open-source notch UI, media, calendar, file shelf, HUDs. | A valuable interaction reference, not a developer-repair workflow. Do not copy its GPL code into a permissively licensed project. |
| **Alcove / DynamicLake** | Polished Dynamic Island aesthetics, live activities, notifications and general-purpose utilities. | High visual benchmark; not the specific verified-repair use case. |
| **Super Notch** | Agent-session discovery/resumption for Claude Code, Codex, Cursor and others, voice/dictation, usage. | Watching/resuming a session differs from producing a test-backed patch capsule. |
| **Agent Notch / Kannu / Notchy / NotchIA** | Agent activity indicators, permissions, session or usage monitoring in notch surfaces. | Patchbeam must avoid competing chiefly on status lights or token counters. |
| **Padu and worktree-oriented agent workspaces** | Agent workspace management, isolated worktrees, diffs/checkpoints. | These make worktrees non-unique on their own; Patchbeam's angle is the **diagnostic-to-proof loop as a tiny peripheral UI** that complements editors. |

**Research conclusion:** The defensible promise is not “AI in the Mac notch,” since competitors already do that. It is **“the shortest trustworthy journey from a real developer failure to a verified, reviewable fix.”** Do not present worktree isolation or session monitoring alone as novel.

**Design inspiration, not implementation copying:** Adopt the immediacy of NotchNook-style expansion and Alcove-like restrained motion. All code, branding, icons, written copy, animations, and visual assets must be original or appropriately licensed. See source links in §29.

# 3. Audience, job, and opportunity

## 3.1 Primary persona: working developer

- Uses VS Code, Cursor, Zed, Xcode, terminal, Claude Code or Codex.
- Has several local repositories and often switches between code, terminal output, CI errors, and AI agents.
- Wants low-friction help with a failing unit test, TypeScript error, compiler error, or reproducible bug.
- Distrusts AI claims that a fix “works” without the actual command, exit code, and changed files.
- Values excellent macOS interaction quality and little desktop clutter.

## 3.2 Secondary personas

- **Agent-heavy builder:** runs agents alongside an editor, wants review rather than transcript surveillance.
- **Maintainer:** wants a small reproducible patch and captured verification to turn into a PR.
- **Developer demo/portfolio author:** wants a beautiful, demonstrable native app that can prove it actually works.

## 3.3 Jobs to be done

1. “When my test fails, help me capture enough context without context-switching.”
2. “When an agent edits my code, keep changes isolated so my current work is safe.”
3. “When an agent says it fixed something, show me real tests, caveats, and its exact diff.”
4. “When the task finishes, let me return to the editor with the patch ready to inspect.”
5. “When I have two fixes running, tell me only which needs attention.”

# 4. Goals, constraints, and measures

## 4.1 P0 product goals

- Delightful, responsive notch presence with collapsed/expanded/review states, keyboard access, focus preservation, and correct placement on notched laptops.
- Functional paste-text / drag-file diagnostic intake and repository selection.
- One **real agent provider integration** (recommended first: Codex app-server where stable and installed), plus a fully deterministic demo adapter for tests; second provider is P1 only if reliable.
- Git worktree creation, scoped execution, real subprocess/event streaming, bounded retries, and robust lifecycle cleanup.
- Real verification commands, exit codes, captured logs, changed-file list, diff, and explicit handoff/apply action.
- Persistence/recovery, permission clarity, error states, excellent docs, a usable source build, and an actual demo video.

## 4.2 Release goals: measurable, not magic promises

| Dimension | Target and proof method |
|---|---|
| Golden-path success | 100% of deterministic fixture repair scenarios pass on supported test hosts; one live provider run documented separately. |
| Startup | Cold-start UI visible within 2 seconds on reference Apple-silicon machine; measure actual p50/p95. |
| UI | 60 fps target during expand/collapse on reference Mac, no visible stutter; performance capture attached. |
| Interaction | Expand response ≤150 ms target, keyboard-focus behavior verified with UI tests. |
| Idle footprint | Target <1% CPU averaged over 5 minutes idle on reference machine; memory budget target <180 MB; report measured values rather than assuming. |
| Reliability | No unintended active-worktree mutation in adversarial fixture tests; safe recovery from agent termination and app restart. |
| Accessibility | Complete keyboard path, meaningful VoiceOver labels, reduced-motion mode, contrast check; no color-only status. |
| Installation | Fresh-user install walkthrough successfully repeated on a clean Mac user account or clean VM. |
| Documentation | A beginner can build using the exact commands in README, with commands validated in CI where feasible. |

If actual measured budgets differ, report them in `docs/QUALITY_REPORT.md` and remediate meaningful regressions. Never mark a test “passed” without an executed test result.

## 4.3 Explicit non-goals (v1)

- No automatic GitHub PR creation, pushing, merging, or production deployment.
- No autonomous always-on codebase monitoring, hidden clipboard logging, or reading all active windows.
- No built-in LLM subscription, agent reimplementation, cloud account, remote collaboration, or phone app.
- No unsupervised background retries on a customer's live repo.
- No all-framework “just works” test command inference; recommendations are reviewable, fallbacks are clear.
- No guarantee that AI fixes are correct or that a Git worktree blocks access to other files.

# 5. Scope and priorities

| Priority | Deliverable | What “done” means |
|---|---|---|
| **P0** | Native notch shell | Real NSPanel/AppKit positioning; collapsed, glance, expanded, keyboard and multiple-display behavior. |
| **P0** | Onboarding + permission ledger | Explain providers and data boundaries; detect tools; no permission sought before corresponding action. |
| **P0** | Capture diagnostic | Paste multiline stack trace; select `.log`/`.txt`; optional text drag; trim with preview. |
| **P0** | Repo binding | User picks repo; Git root/base/dirty-state checks; recent list; path is not auto-exfiltrated. |
| **P0** | Patch Capsule | Durable state machine, event log, timestamps, error handling, retention actions. |
| **P0** | Agent execution | One real documented provider integration and deterministic fixture adapter, with approval surfaces. |
| **P0** | Worktree lifecycle | Unique branch/path, no overwrites, bounded cleanup, safe leftover recovery. |
| **P0** | Verification | Explicit configurable test command; run output, exit status, duration, evidence captured. |
| **P0** | Review + handoff | Diff, file list, tests, Copy summary, Open in Editor, Apply with approval, Discard safely. |
| **P0** | QA + demo + release hygiene | Tests, packaging scripts, documented build, real media, README, source/license/security docs. |
| P1 | Claude Code provider adapter | Uses documented versioned CLI/hook behavior; robust parity for status and approvals. |
| P1 | Terminal helper | `patchbeam capture`, `patchbeam open`, `patchbeam status` with safe local protocol. |
| P1 | Screenshot/OCR intake | Explicit user-triggered ScreenCaptureKit selection and redaction preview. |
| P1 | IDE handoff | VS Code/Cursor/Zed opening at changed files and relevant line. |
| P1 | CI log import | User-supplied file/URL plus opt-in GitHub authentication; no invisible scraping. |
| P2 | Evidence export | Markdown/JSON proof capsule; optional shareable report. |
| P2 | Multiple agents / parallel candidates | Only after proven conflict-free orchestration and extra approval UX. |
| P2 | Local model connector | Only if it supports equivalent permissions and end-to-end verification. |

**Anti-scope-creep rule:** Do not begin P1/P2 until all P0 acceptance gates pass. A simulated agent is for tests/demo fixtures, never substituted for real-provider support in the release claims.

# 6. Essential user journeys

## Journey A — Fix a test failure (golden path)

1. User runs a local test and copies its traceback, then opens Patchbeam with `⌃⌥Space` (configurable, conflict-checked).
2. Compact prompt appears adjacent to the notch: **“What broke?”**, with paste/drop area and optional free-text goal.
3. Paste arrives; a preview shows its first lines and byte count. User can redact or edit before sending to provider.
4. Patchbeam proposes a recently approved repository only if high confidence; otherwise user selects it. Display dirty-worktree warning and `HEAD` commit; do not silently include unstaged edits.
5. User sees **“Fix in a separate worktree”**, provider name, repo, approved verification command, network/permission policy, and an estimated—not guaranteed—task budget. User clicks **Start Repair**.
6. App creates unique worktree from the selected base commit. If creation fails, show actionable error and leave repo unchanged.
7. Real agent starts with narrowly scoped instruction and the approved diagnostic. Notch communicates specific lifecycle steps and pauses for approvals. User can stop safely.
8. On agent completion, host runs the selected verification command inside worktree, subject to authorization. It captures stdout/stderr, exit code, test summary if parseable, elapsed time, and executable path.
9. **Verified** is displayed only if the selected command exited 0 and the result belongs to the current worktree content/version. A passing verification is not a guarantee of correctness; say “Selected checks passed.”
10. User reviews changed files, meaningful patch, original failure, actual checks, and warnings; then chooses `Open in Editor`, `Apply to My Branch…`, `Keep Capsule`, or `Discard Worktree…`.
11. `Apply` requires explicit confirmation, checks repo dirty/conflict state and patch provenance, and uses safe Git operations; if conflict detected, stop without destructive overwrite and offer manual handoff.
12. Capsule remains with provenance, verification evidence, and final status. No push, commit, or merge occurs without a separately designed future approval flow.

**Acceptance:** This journey works with the deterministic fixture and a real connected provider; user can independently run the documented fixture test and observe matching evidence.

## Journey B — Fix requires permission

Agent asks to execute a potentially dangerous command or access beyond its boundary. Collapsed notch becomes a persistent but non-stealing attention cue. Expanded action clearly shows **exact command, working directory, reason, affected scope, requester, and potential risk**, plus Deny / Allow Once. Expired or stale requests are un-actionable. No “always allow” shortcut in v1. If provider doesn't offer a safe approval bridge, defer to that provider's own terminal UI and show “Approval required in terminal,” not a fictional Allow control.

## Journey C — Failure to verify

Agent returns a patch but tests fail. Show **“Needs work”** (not success), failing command + exit code + clipped output, Review anyway, Retry with failure evidence (bounded, explicit click), or Stop. A maximum of **one** user-approved automated follow-up per capsule in v1 prevents loops and runaway costs. Any new edits invalidate old verification evidence until rerun.

## Journey D — No AI installed

App still launches and shows a polished, interactive demo using the bundled deterministic **demo repository**, labeled “Demo — no model used.” There is a direct setup link/instructions for installing and authenticating a supported agent CLI. All unsafe/apply actions are disabled when on an illustrative data-only scenario; the scripted fixture path can still prove real Git and test actions locally.

## Journey E — Restart / disconnect

If app closes or crashes during a task, on restart reconcile persisted capsule state against process/session status. Mark `Interrupted` when process cannot be proven live, preserve logs/worktree, offer Resume only if adapter supports it or Start New Attempt from same base; never claim success or silently delete. System sleep, closed lid, canceled run, provider logout and stale socket are first-class states.

# 7. The visual and interaction identity

**Creative direction:** “precision instrument meets calm editorial design.” The notch feels like a small glowing seam between developer and working code. It should look at home on the macOS menu bar without copying another notch app.

## 7.1 Visual tokens

- **Background:** near-black graphite `#0D1016`, elevated surface `#171C26`, separator `#303846`.
- **Text:** off-white `#F5F7FB`, secondary `#A8B2C4`, subdued `#758298`.
- **Brand accent:** electric periwinkle `#8C93FF` / blue `#5C8DFF` subtle two-stop gradient; restrained, not neon all the time.
- **Status:** executing blue `#79B5FF`; ready green `#59D5A3`; warning amber `#FFC36E`; failed coral `#FF7D83` plus icon+label.
- **Typography:** native San Francisco system font; monospaced SF Mono/Menlo for paths, commands, commit hashes, and code.
- **Radius:** compact capsule full pill; expanded panel 22–26 pt; inner surfaces 12–14 pt.
- **Stroke/shadow:** 1 px low-contrast edge and subtle ambient shadow, avoiding bright borders on idle.
- **Material:** opaque enough for contrast; blur only where reliable and not distracting. Respect Increase Contrast and Reduce Transparency.
- **Density:** maximum of 2 pieces of information in collapsed view; maximum of 3 primary actions in any contextual region.
- **Originality:** bespoke glyph for Patchbeam: two small offset rays closing into a diff `+` mark. Do not adopt NotchNook's logo or proprietary shape assets.

## 7.2 Four visual states

**S0 — Dormant:** physically plausible rounded black island contiguous with the camera housing's visual footprint (never paint important content under the real camera cutout). No text; optional tiny peripheral signal when work exists. Click or hover-with-dwell opens a glance. `Escape` collapses.

**S1 — Glance:** width roughly 270–360 pt, height 50–72 pt subject to screen geometry; shows active capsule `Repo · Diagnosing` plus a thin animated progress rail (indeterminate unless actual progress known). Most recent action gets a succinct status. No continuous throbbing or notification barrage.

**S2 — Expanded cockpit:** width roughly 400–500 pt, content height adaptive ≤ min(580 pt, 70% of usable display). Header with repo chip and capsule count; main focus card; segmented *Activity / Changes / Proof* views, scrollable bounded areas; unobtrusive “Stop / Open / Close” actions. Use native code monospacing and selectable text.

**S3 — Review ready:** a quiet completed cue, “Selected checks passed”, patch stats (e.g. `3 files · +18 −7` only if computed from Git), proof card with command and status, then **Review changes** primary. Error state instead shows exact failure, never green.

**S4 — Intake:** expands from notch into a lightweight input card with paste/drop, repository picker, provider selector, verification command and scope preview. Do not overwhelm first launch: progressive disclosure into `Advanced`.

### Simple wireframes (not pixel specifications)

```text
Dormant:               ▰▰▰▰ camera notch ▰▰▰▰

Glance:            ╭────────────────────────────╮
                   │ ● api-service  Verifying…  │
                   ╰────────────────────────────╯

Expanded:        ╭──────────────────────────────────────────╮
                 │ PATCHBEAM        api-service      ⌘,  × │
                 │                                          │
                 │ ● Repair 04   Running tests…             │
                 │ ──────────────────────────────────────── │
                 │ Activity       Changes        Proof      │
                 │ $ npm test                               │
                 │ 24 passed  •  1 failing                  │
                 │                                          │
                 │       [Stop]     [Open in Editor]        │
                 ╰──────────────────────────────────────────╯
```

The actual interface must be more refined than ASCII; use the same content hierarchy.

## 7.3 Motion and haptics

- Spring-based expand/collapse with approximate duration 220–320 ms; interruptions must be seamless, no scale jumps.
- Status updates fade/slide over 120–200 ms; **reduced motion** replaces positional movement with modest crossfades.
- Tiny moving beam/ray only for actual execution, not decorative idle animation.
- No perpetual high-frequency timers or 60 fps loop when idle.
- Hover has a ~180–250 ms dwell to prevent accidental activation; click and hotkey work instantly. Touch/trackpad behavior should be tested on hardware.
- Never steal text-input focus from editor merely because a status changed or an agent finished.
- Accessible feedback: VoiceOver announces “Verification failed” when foregrounded, without incessant announcements in background.

## 7.4 High-value microinteractions

- Dragging `.log` onto top-center zone previews a luminous hairline and a `Drop log to inspect` label; no giant overlay over menu items.
- While agent runs, a faint beam shifts from left (diagnosis) to right (proof); phase descriptions remain explicit.
- Error line within proof card is copyable, with `Copy failure` on hover/focus.
- A “worktree safe” shield icon opens a plain-language explanation of what isolation does/does not guarantee.
- The same app supports keyboard-only creation, stopping, review, and handoff.

# 8. Native notch and display behavior

**Physical truth:** macOS apps do not create pixels inside the camera hardware cutout. Implement a borderless AppKit-hosted window **around/below** it, respecting display safe areas and preserving camera/menu-bar behavior. Never attempt to render content behind or over a camera, fake a custom notch via screen recording, or modify OS internals.

### Required implementation

1. Use SwiftUI for content, AppKit window/panel control for geometry and interaction; prefer an `NSPanel` or equivalent appropriate nonactivating/click-through overlay when collapsed.
2. Query `NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` where applicable. Derive geometry from actual display dimensions/safe areas, **not hardcoded MacBook product model identifiers**.
3. Implement a central `NotchGeometryEngine` with `screenFrame`, `safeArea`, `notchApproximation`, `panelFrame`, `displayScale` and `layoutMode`. Include bounds tests.
4. Position the panel on whichever display the user selected in Settings (default: built-in notched display where detectable); support external displays with a floating capsule variant.
5. Recompute on display connection/disconnection, resolution, scaling, menu bar relocation, Spaces/full-screen transitions, sleep/wake, notch display changing, and layout-direction changes.
6. Use appropriate documented `NSWindow.CollectionBehavior` choices such as joining spaces/full-screen as validated by actual tests. Do not combine mutually exclusive flags or assume overlays always work above secure/full-screen screens.
7. Respect active screen sharing, macOS permission prompts, system UI, and secure content; provide `Hide in fullscreen` and `Hide during screen sharing` user preferences if reliable detection is possible; otherwise provide a manual privacy toggle.
8. Expanded panel must never extend off-screen, obscure critical menu bar system items, trap focus, or intercept unrelated clicks.
9. Collapsed hit-testing should cover only the actual intended target; click-through elsewhere. No invisible 500×500 click shield.
10. Add manual **Reposition / Reset Layout** in preferences; user can recover if OS geometry APIs differ.

### Minimum display test matrix

| Case | Expected behavior |
|---|---|
| MacBook Air with notch, normal desktop | Centered, unobscured, integrated silhouette. |
| MacBook Pro with notch, normal desktop | Same, scaled appropriately. |
| Different resolutions/scaled display | No clipped text or off-screen controls. |
| External non-notched monitor as primary | Floating capsule or preference-based move, no fake camera cutout. |
| Multiple spaces / Stage Manager | Consistent visibility according to user setting, no stuck panel. |
| Native app fullscreen | Documented behavior tested; toggle and escape work or fallback presented. |
| Display unplugged while expanded | Re-home safely to available display. |
| High contrast, reduce motion, VoiceOver | Readable, navigable, accessible. |
| Mac without notch / VM | Fully functional capsule fallback; **not evidence of real-notch hardware fit**. |

# 9. Onboarding and settings

**First-run steps:** Welcome → device/layout preview → local repository selection (optional) → detect installed provider(s) and authentication state **without reading secrets** → configure verification default → try real fixture demo or create first capsule → optional global shortcut / login item. No mandatory account, telemetry, Accessibility, Screen Recording, Full Disk Access, or microphone permission.

Settings sections: **General** (start at login off by default, shortcut, reduced motion override), **Appearance** (dark/glass-optional, compact size, hover), **Display** (target screen/fullscreen behavior), **Projects** (approved roots, commands), **Agents** (provider executable, version, capabilities, approvals, default budget), **Privacy** (data retention, export/delete, log redaction and permission ledger), **About** (version, links, diagnostics export).

Preflight error messages must be actionable: “Codex CLI not found,” “Git is missing,” “Selected directory is not a Git repository,” “Agent authentication expired,” “Permission approval must happen in your terminal,” “The chosen check requires a command,” “Worktree creation failed because [reason].” No `Unknown error` as the only message.

# 10. State machine and domain model

## 10.1 Capsule state machine

```text
DRAFT -> READY -> PREPARING_WORKTREE -> QUEUED -> RUNNING
                                  |                    |
                                  v                    v
                                FAILED         AWAITING_APPROVAL
                                                       |
                                              (allow/deny/timeout)
                                                       v
                                                    RUNNING
RUNNING -> VERIFYING -> REVIEW_READY_VERIFIED -> APPLIED | KEPT | DISCARDED
                  |                   ^
                  +-> REVIEW_READY_FAILED -> RETRYING --+
RUNNING/VERIFYING/QUEUED -> CANCELLING -> CANCELLED
any recoverable active state -> INTERRUPTED -> RECONCILING -> RESUMABLE | NEEDS_RESTART
```

Each transition is validated, timestamped, idempotent where practical and persisted before revealing terminal success. *“Verified” is never set by model text.* Only host-owned verification results can set it, for an identified patch revision. Cap retry loops. User may always keep a failed patch for manual review, clearly labelled failed.

## 10.2 Data contracts (illustrative; implement with Codable/SQLite)

```text
Project: id, canonicalRoot, displayName, defaultVerificationCommand, consentPolicy, lastUsed
Capsule: id(UUID), projectId, title, sanitizedDiagnostic, baseCommit, sourceFingerprint,
         worktreePath, branchName, provider, agentSessionId?, status, createdAt, updatedAt,
         currentPatchFingerprint?, attemptCount, warnings[], disposition?
AgentEvent: id, capsuleId, sequence, timestamp, kind, phase, summary, payloadRedacted
ApprovalRequest: id, capsuleId, providerRequestId, command?, cwd?, permissions[], risk,
                 createdAt, expiresAt?, status, responseAt?
Verification: id, capsuleId, patchFingerprint, argv[], cwd, startedAt, endedAt,
              exitCode?, signal?, stdoutLogPath, stderrLogPath, parsedCounts?, result
PatchArtifact: capsuleId, baseCommit, patchFingerprint, changedFiles[], diffFile,
               binaryFileNotes[], generatedAt
```

**Persistence:** `~/Library/Application Support/Patchbeam/` with SQLite migrations (WAL), bounded logs, and user-visible retention settings. Avoid putting secrets in SQLite. No reliance on arbitrary plaintext state files for coordination. Store keychain items only if a future integration truly requires keys.

## 10.3 Event normalization

Providers emit different message formats. Convert them into a documented versioned `AgentEvent` protocol with event types `session_started`, `thinking`, `tool_proposed`, `approval_requested`, `tool_started`, `tool_finished`, `edit_observed`, `message`, `completed`, `failed`, `cancelled`, `heartbeat`. Preserve ordering and provider IDs; handle duplicate/out-of-order events without duplicate UI actions. Never display `tool_finished` as success when its exit status is unknown.

Example normalized event:

```json
{
  "schema": 1,
  "capsuleId": "a1d2e7f0-0000-4000-8000-000000000001",
  "sequence": 23,
  "timestamp": "2026-11-11T18:00:00Z",
  "kind": "tool_finished",
  "phase": "editing",
  "summary": "Updated validator.ts",
  "safeMetadata": { "exitCode": 0, "durationMs": 322 }
}
```

# 11. Functional requirements by ID

| ID | Requirement | Acceptance observation |
|---|---|---|
| PB-001 | Hotkey/click opens intake without stealing focus on passive updates. | Key command and XCUITest; no unsolicited key-window switch. |
| PB-002 | Diagnostic paste/drop preview with user edit/redact. | Multiline Unicode, >100 KB, empty file, and unsupported file tests. |
| PB-003 | User-controlled project-root authorization. | No implicit all-disk scan; repo change requires selection. |
| PB-004 | Dirty repo handled safely. | Worktree based on HEAD only; warning about uncommitted work. |
| PB-005 | One worktree/unique branch per capsule. | `git worktree list` verifies; existing branches untouched. |
| PB-006 | Real provider availability and authentication check. | Missing/logged-out CLI shows setup, no fake connected state. |
| PB-007 | Stream normalized real events. | Reconnect/drop/duplicate event fixture tests. |
| PB-008 | Approval UI with exact risk scope; no default bypass. | Deny, allow-once, stale, unsupported bridge paths tested. |
| PB-009 | Stop cancels agent process group safely. | Cancellation leaves base repo intact and logs available. |
| PB-010 | Verification command opt-in and explicit. | Exit code, signal and logs match shell-free process execution. |
| PB-011 | Verification evidence tied to patch fingerprint. | Editing after pass invalidates “verified” status. |
| PB-012 | Diff from base is visible, copyable and correct. | Text, deleted, renamed, whitespace, binary-file summaries. |
| PB-013 | No silent apply/commit/push/merge. | Fixture asserts base branch untouched before approval. |
| PB-014 | Apply handles conflicts non-destructively. | Dirty destination/conflicting patch tests; no force/reset. |
| PB-015 | Durable capsule recovery and bounded retention. | Force quit/restart; no false success, no lost user work. |
| PB-016 | Multi-display placement and fallback. | Geometry unit tests plus physical hardware smoke. |
| PB-017 | Complete keyboard, VoiceOver, contrast, reduced motion. | Accessibility checklist + automation/manual records. |
| PB-018 | Readme source build and release install tested. | Fresh account/VM walkthrough logged. |
| PB-019 | Authentic media files and links. | Files readable; videos show genuine fixture and/or real run. |
| PB-020 | Safe secret/log processing. | Redaction tests; no raw secrets in metrics, archives or demo. |
| PB-021 | Honest demo-mode watermark/state. | Mock and live provider states visually distinguishable. |
| PB-022 | Empty states and error states are polished and actionable. | UX snapshot matrix reviewed in light/dark/accessibility. |

# 12. Agent runtime, adapters, and execution safety

## 12.1 Recommended integration order

**First choice: Codex app-server**, if the installed CLI version documents the thread/event/approval operations needed; use its official application integration surface to create sessions, stream events, and honor sandbox and approval modes. Validate the installed protocol at build time, pin minimum supported version, and include contract tests. If reliable direct Swift interop is awkward, implement a tiny narrowly scoped local sidecar (Rust or Node only if unavoidable); keep the user-facing app native SwiftUI/AppKit. Avoid unversioned log scraping as the primary transport.

**Second choice (P1): Claude Code** via documented headless/structured output and hook mechanisms. Confirm supported callback semantics using current official docs and actual CLI version before advertising one-click approvals. Where interactive approvals cannot be safely brokered, display the request and direct the user to the owning terminal instead. Do **not** fake protocol support through guessed JSON fields.

**Deterministic DemoAgent:** First-class adapter which takes a known bug fixture through the same state transitions, creates a genuine Git diff, and runs a real verification command without contacting a model. It is labeled as a scripted demo. It is not a substitute for one production-capable agent adapter.

**Credentials:** Prefer already authenticated provider CLI. Do not embed provider secrets or pass unredacted environment dumps to logs. User is responsible for provider login/subscription/API usage. Show provider name before every run.

## 12.2 Core process interface (conceptual)

```swift
protocol AgentAdapter {
    var providerID: String { get }
    func probe() async -> ProviderAvailability
    func start(_ request: AgentRunRequest) async throws -> AgentSessionHandle
    func events(for handle: AgentSessionHandle) -> AsyncThrowingStream<AgentEvent, Error>
    func respond(to request: ApprovalRequest, decision: ApprovalDecision) async throws
    func cancel(_ handle: AgentSessionHandle) async
}
```

Unsupported capabilities must be explicit in `ProviderAvailability` and hide/disable their corresponding buttons. Store a capability matrix per supported version. Do not implement a fake no-op `respond()` method.

## 12.3 Execution rules

- Use `Process` with **executable URL plus an argv array**, not a pasted command in `sh -c`. Explicitly parse user-approved test commands or let user choose executable + arguments. Quoting must not be silently reinterpreted.
- Canonicalize/revalidate allowed repo root, worktree path and every file path with symlink-escape checks; protect against traversal, unusual Unicode and colliding paths.
- Give each capsule a unique execution ID, process group, capped log streams, timeouts and explicit cancellation. Never kill unrelated processes by matching a process name.
- Avoid importing entire shell environments. Construct a minimal controlled environment and the PATH necessary to find opted-in tools; clearly explain unavoidable provider access to its own account and runtime context.
- Prevent concurrent **apply** operations into the same target branch. Agent editing can run in separate worktrees but set v1 default concurrency to one to prioritize stability.
- Record final process return codes. Distinguish transport failure, approval denial, model refusal, timeout, cancellation and test failure.
- Enforce budget guardrails: configurable overall wall-clock timeout, process output limit, retry count; notify before provider usage where cost is unknowable.
- Avoid `--dangerously-skip-permissions`, `--yolo`, `--full-auto`, unreviewed shell policy bypasses, or equivalent unrestricted modes by default.

## 12.4 Worktree and Git details

- Validate `git rev-parse --show-toplevel`, active branch/DETACHED HEAD, `HEAD` SHA, and repo status before creating anything.
- Create app-owned worktree under `~/Library/Application Support/Patchbeam/Worktrees/<capsule-id>/` with a unique `patchbeam/<capsule-short-id>` branch, using safe argument-based Git invocation. Account for spaces in paths.
- Dirty source files stay where they are; new worktree starts from committed `HEAD`. Show a warning that uncommitted changes are **not included**. If initial `HEAD` absent, explain unsupported repository state.
- Do not copy `.env`, untracked secrets, ignored files, or submodule credentials into a worktree by default; explain that Git-tracked sensitive files still exist there.
- Before starting run, record base commit plus a fingerprint of worktree state. Before verification and apply, re-evaluate status/diff; binary and renamed files need honest summaries.
- A “patch” may contain additions/deletions; present entire diff and, for oversized diffs, a readable fallback file in an editor rather than truncating without warning.
- Applying: first dry-run/check against target; if clean and exact expected base, use an explicitly described safe patch application strategy, preserve rollback artifact, and verify post-apply diff. If source changed or conflicts occur, fail closed and open the separate worktree in editor for manual merge. Never `git reset --hard`, `git clean -fdx`, force push, or overwrite dirty files.
- Discarding app-owned worktrees requires a second confirmation when modified/uncommitted output exists. Retain branch/log/evidence by default until user chooses cleanup or retention period expires, with clear warning.
- Worktree cleanup is never used to hide failure. Uninstall instructions explain where capsule files remain.

## 12.5 Important security caveat

Worktrees isolate **Git checkout state**, not filesystem/network permissions. A local coding agent may have access to user files or the internet under its own runtime policy. Prefer the provider's supported sandbox and a least-privilege approval mode; an optional separate VM for especially untrusted repos is a future enhancement. Do not describe worktrees as “secure sandboxes.”

# 13. Verification engine and proof semantics

**Proof belongs to the host, not the model.**

Each project has an explicitly approved `VerificationRecipe` — an executable, array of arguments, working-directory policy, timeout, and optional expected file/artifact patterns. Sample recommendations (user must confirm): `swift test`, `npm test -- --runInBand`, `pnpm test`, `pytest -q`, `go test ./...`, `cargo test`. Do not automatically guess and execute arbitrary scripts or `package.json` lifecycle commands merely because they exist.

Execution steps:

1. User approves recipe before first run; updates to recipe require reapproval.
2. Snapshot worktree patch fingerprint and command identity.
3. Run via safe process API with capped output, duration and cancellation support; record cwd, exit code and signal.
4. Parse known test formats opportunistically, but the raw exit code remains authoritative. Unknown framework: show “Command exited 0” or “Command exited 1,” not fabricated test counts.
5. Compare post-test worktree to fingerprint. If command mutates tracked files, invalidate proof and show “Tests changed files; review and re-run.”
6. Success UI says `Selected checks passed` alongside exact command and recorded time; optional parsed `24 tests passed` only when parser verified it.
7. If command exits 0 but no tests ran, test command is a no-op, or run was canceled, make no blanket “verified repair” claim; present warning. Detect known no-tests signals when feasible.
8. If no recipe exists, permit Review with `Not verified — no check configured`, clearly differentiated from a successful run.

**Optional stronger proof:** For deterministic fixture, prove red-before / green-after by first running the same check on the base state and recording failure, then on the patch state and recording success. For general repositories, baseline runs can be expensive: make them user-approved and do not assume reproducibility.

# 14. Diagnostics, privacy, and security requirements

## 14.1 Trust model

Assume pasted logs can contain secrets, adversarial prompt injection, personal data or malicious escape sequences; repositories can contain symlinks, malicious tests, malformed Git state, and indirect prompts. Distinguish *untrusted diagnostic text* from the trusted user task. Diagnostics must not modify system instructions or grant access. Providers may still be vulnerable to malicious content; neither redaction nor prompt design is foolproof.

**Data movement:** Local app stores capsules locally. The actual AI provider may receive diagnostic/context data and may have access to the selected repo under its own policy. Before Start, show provider, selected repository, preview of supplied text and a plain-language disclosure. No secret uploads for analytics. Default telemetry **off**; if telemetry eventually exists, require explicit opt-in and never include paths, source, prompts or logs.

## 14.2 Required controls

- Entitlements minimized; no Full Disk Access, Accessibility or Screen Recording required for basic pasted-log → repair flow.
- If screenshot intake ships later, request Screen Recording only on explicit capture with system picker, and include a preview/redaction step. If user denies, paste/drop flow must continue working.
- Configurable local regex/entropy hints for common keys, tokens, bearer headers and email addresses before sending or exporting. Provide user override and warn that scanner is fallible.
- Mask ANSI terminal escape sequences and control characters before rendering logs; prevent oversized output from freezing SwiftUI views.
- Constrain log sizes (e.g., 2 MB per stream in UI with full capped archive by policy); backpressure on high-volume subprocesses.
- Sanitize Markdown and do not render live HTML/JavaScript from agent output in privileged WebViews.
- Validate local IPC clients if using Unix sockets: owner-only socket directory/permissions, no arbitrary shell commands, protocol version, request size cap, and per-operation authorization.
- Use `OSLog` with private data semantics; do not log prompt contents, filesystem secrets or tokens.
- No automatic execution of third-party downloaded binaries. Ensure all dependencies have pinned versions and reviewed licenses.
- Save patch history in a user-deletable location; include “Delete All Local History” and retention options.
- Signing/notarization required for a polished public release whenever credentials exist; no programmatic Gatekeeper bypass in install scripts.

## 14.3 Threat table

| Threat | Mitigation | Residual risk |
|---|---|---|
| Prompt injection in logs/repo | Treat as data, narrow user task, permission gates, no silent high-risk tools | Provider model may still be deceived. |
| Malicious verification script | Explicit review/approval, timeout, provider sandbox where possible | Scripts can have side effects; worktree alone does not contain them. |
| Secret leakage through agent | Preview/redact, selected repo only, provider notice, optional strict sandbox | Git-tracked secrets/CLI access remain risk. |
| Symlink/path escape | Canonicalization and revalidation before operations | Time-of-check/time-of-use races require careful handling. |
| Patch applied over user edits | Preflight `git` checks, dry-run, no force | Manual merge may be required. |
| UI approval race | ID/version/expiry validation; one response; deny on stale | Provider semantics vary. |
| Fake success | Host-only exit-code proof tied to patch fingerprint | Passing tests do not prove complete correctness. |
| Release supply chain | Signed builds, notarization, reproducible CI evidence, checksums | Developer signing trust and dependencies still matter. |

# 15. App architecture and repository shape

**Preferred:** Swift 6, SwiftUI, AppKit, Swift Testing/XCTest/XCUITest, Foundation `Process`, SQLite through a stable maintained library or minimal direct wrapper, OSLog. macOS 15 target for first release with macOS 26 regression testing; Apple silicon first. Core business logic testable without windows or a real provider.

```text
Patchbeam/
├── Patchbeam.xcodeproj              # or a reproducibly generated project, checked in
├── Package.swift?                  # only if actually part of chosen build
├── Sources/
│   ├── App/                        # main app, menu extra/settings/onboarding
│   ├── NotchUI/                    # panel, hover, geometry, keyboard/focus
│   ├── DesignSystem/               # theme, motion, reusable SwiftUI views
│   ├── Capsules/                   # models, state machine, persistence
│   ├── Diagnostics/                # paste/drop intake, validation, redaction
│   ├── GitCore/                    # Git process client, worktrees, diff/apply
│   ├── Agents/                     # AgentAdapter + Codex + Demo adapters
│   ├── Verification/               # recipes, runner, parsers, proof
│   ├── Permissions/                # approval policies and prompts
│   └── Infrastructure/             # logging, IPC, process, cancellation
├── Tests/
│   ├── Unit/
│   ├── Integration/
│   ├── UI/
│   └── Fixtures/
│       ├── broken-python/          # deliberately failing fixture, isolated
│       ├── broken-typescript/      # optional secondary fixture
│       └── malicious-paths/        # symlink/dirty repo/conflict scenarios
├── scripts/
│   ├── bootstrap.sh                # checks prerequisites; no surprise installs
│   ├── build.sh
│   ├── test.sh
│   ├── fixture-demo.sh
│   ├── record-demo.sh
│   ├── package-dmg.sh
│   └── release.sh                   # signs/notarizes only if credentials present
├── docs/
│   ├── PRD.md                      # this spec
│   ├── ARCHITECTURE.md
│   ├── SECURITY.md
│   ├── PRIVACY.md
│   ├── TROUBLESHOOTING.md
│   ├── QUALITY_REPORT.md
│   ├── DEMO_STORYBOARD.md
│   ├── RELEASE_CHECKLIST.md
│   ├── adr/
│   └── media/                     # optimized authentic preview media
├── .github/workflows/
│   ├── ci.yml
│   └── release.yml
├── README.md
├── AGENTS.md                       # project coding/test rules for future agents
├── CONTRIBUTING.md
├── SECURITY.md
├── LICENSE                          # choose consciously before publishing
└── CHANGELOG.md
```

**Layer boundaries:** UI reads a `CapsuleStore`/`AppModel` on `@MainActor`; async services run off main; adapters cannot modify the UI state machine directly; persistence is transactionally consistent; Git/verification code has no dependency on UI. Use dependency injection for fake process runners and geometry providers. Avoid massive singleton coordinators and enormous SwiftUI views.

**Error handling:** typed domain errors with user message, diagnostic code and optional recovery action. No `try!`/force unwrap on untrusted data; explicit cancellation propagation; every async task tracked and terminated/reconciled as needed. Strict concurrency diagnostics enabled.

# 16. Detailed fixture and automation requirements

## 16.1 Golden fixture

Include a tiny **self-contained Python repository** (no external Python packages) with:

- `calculator.py` where `total(items)` deliberately subtracts the tax instead of adding it.
- `test_calculator.py` using `unittest` and asserting the correct result.
- A README explaining the seeded bug and correct behavior.
- Script to initialize a temporary Git repo, commit the broken baseline and run `python3 -m unittest -v` expecting nonzero.
- DemoAgent script edits the bug **inside worktree only**, then re-runs `python3 -m unittest -v` expecting exit 0; preserve logs and patch fingerprint.

Tests must validate the baseline is red and patched version green, and confirm the base checkout is still broken until user explicitly applies. This fixture provides deterministic tests, media, and live onboarding without API bills. Use a separate real provider smoke test on a similar fixture with model authentication when configured.

## 16.2 Tests to implement

**Unit:** geometry calculations (notched vs non-notched, Retina scales, multi-display bounds), state transition legality, dedupe/event ordering, redaction, command-argument parsing, verification fingerprint, log truncation/ANSI stripping, persistence migrations, UI view-model empty/error states.

**Git integration:** repo path with spaces/Unicode; dirty initial repo; untracked `.env`; symlink out of root; detached HEAD; missing HEAD; branch collisions; renamed/deleted/binary files; submodules; worktree left behind; apply on changed target branch; conflict; cancellation during patch; cleanup without touching source.

**Provider integration:** installed+authenticated; missing CLI; expired auth; malformed JSON/events; out-of-order/duplicate events; interrupted stream; huge output; provider refusal; approval allow/deny/stale; sandbox refusal; crash during execution; unsupported provider capability.

**Verification:** command exit 0 and 1; timeout; signal kill; no tests run; stdout+stderr burst; custom cwd; test mutated tracked files; check fingerprint mismatch; user changed recipe; 0-byte or huge log.

**UI automation:** first run, onboarding skip, create capsule, copy/paste, drag-drop if framework permits, start, approve/deny affordances, stop, proof card, keyboard navigation, VoiceOver attributes, close/reopen, display change mock. Native physical-notch positioning must be manually verified in addition to UI automation.

**Security:** shell injection attempt in repo path, secret regex false positives/negatives, path traversal via IPC, arbitrary socket client, malicious ANSI sequences, stale approval replay, symlink swap, malicious test command warning, no permissions by default.

## 16.3 Commands and evidence

Provide real scripts so the following execute successfully from a fresh clone on supported macOS (adapt Xcode scheme names to the actual project):

```bash
./scripts/bootstrap.sh --check
./scripts/build.sh
./scripts/test.sh
./scripts/fixture-demo.sh --headless
open ./build/Debug/Patchbeam.app    # adjust documented path to actual build output
```

Do not publish illustrative commands that have never been executed. Capture test logs and machine information (macOS version, architecture, Xcode and provider CLI versions, with no secrets) in `docs/QUALITY_REPORT.md`. CI must fail on failing unit/integration tests, not swallow exit codes.

## 16.4 Test execution matrix

- On every PR: static analysis, unit tests, Git fixtures, fixture demo assertions, native build, documentation link/path checks.
- On protected main or release: actual UI automation on a macOS runner with graphical session when supported, app bundle smoke install, package verification, optional provider test with deliberately scoped credentials and spending limits.
- On physical host before release: Air and Pro notch if available (otherwise document which hardware was **not** tested), multi-display, animation recordings, VoiceOver, real provider integration.
- On Mac VM: clean-user installation, GUI flow, automated screenshot comparison and fresh-account regression. **A virtual display has no physical camera notch, so VM success does not replace hardware fit testing.**

# 17. Mac host / VM / agent execution instructions

The coding agent should inspect its actual environment first:

```bash
uname -s
uname -m
sw_vers
xcodebuild -version
xcode-select -p
command -v git
command -v codex || true
command -v claude || true
command -v ffmpeg || true
```

**If running on a real Mac:** use native build, launch and actual GUI/UI tests. Request permission before installing software, modifying global shell configuration, invoking screen capture, creating a VM, signing into providers, or requesting sensitive macOS permissions. Run tests only in generated/explicitly authorized fixture repositories by default; never point first-run automation at the user's real projects.

**If suitable Apple-silicon Mac host is present and VM tools/permissions are available:** optionally create a clean macOS VM using Apple Virtualization framework or an installed supported virtualization application. Use a supported Apple macOS restore image and comply with Apple licensing. Install Xcode/command line tools legitimately, build and test there. Check available RAM/disk first; never overwrite an existing VM. A VM is **not** the production security boundary and cannot prove physical-notch geometry.

**If running on Linux/Windows/agent cloud without macOS GUI:** write and validate platform-independent core code and fixtures where possible, configure CI for macOS, and **report native UI, notch positioning, signing and recording as unverified**. Do not fabricate video of a working app. Surface a clear blocker if macOS GUI isn't available. The coding agent must not assert it used the user's computer when it did not.

**The agent may use computer-use tools only if the actual execution environment grants that ability.** It must not silently install remote-control utilities, bypass system permissions, or claim to have tested GUI interactions that were not executed.

# 18. Demo and documentation media (a release requirement)

Three authentic media assets, captured after the app works:

1. **Hero loop (6–10 seconds; `docs/media/hero.webp` or `.gif`)** — filmed on the actual Patchbeam app, from collapsed island → diagnostic intake → running → review-ready. Use fast-forward only if visibly indicated; no rendered fake UI.
2. **Golden-path walkthrough (45–90 seconds; `Patchbeam-Demo.mp4`)** — screen recording from a real Mac or honestly labeled VM: show original failing fixture test, input, repo/worktree setup, real DemoAgent editing fixture, actual `unittest` red→green evidence, Git diff, and manual apply. Overlay concise subtitles with accurate actions. No synthetic result screens.
3. **Real-provider clip (20–45 seconds; `Patchbeam-Agent-Run.mp4`)** — when an actual Codex or Claude integration is successfully exercised, show real streaming, permission surface if safely supported, and verification evidence. If real provider unavailable, **do not create a fake provider video**; omit and mark as a release gate.

**Media pipeline:** scripted fixture reset → seeded known state → native app launched → system-level screen recording with user's permission (e.g. ScreenCaptureKit or authorized `screencapture`/QuickTime workflow) → crop/redact personal desktop data → compress with `ffmpeg` when available → generate poster and small loop → watch entire output and compare frames to recorded run. Keep original redacted file outside Git if large. A record script can automate fixture setup and build; it must not invent visuals.

**Technical media constraints:** 16:9 demo at 1080p or source resolution where possible; short loop 800–1200 px wide optimized for README; captions readable on mobile; no credentials, personal paths, editor notifications, account names, or private repos. If source screen cannot be captured, write storyboard and label demo **not recorded** instead of adding placeholder media.

**GitHub media behavior:** Embed an actual optimized GIF/animated WebP (depending on verified GitHub rendering) or poster in README, and link to MP4 in GitHub Releases/hosted media; do not depend on HTML autoplay `<video>` working on GitHub README. Verify every link after publishing.

# 19. README-as-product-landing-page specification

README must be an unusually good *actual open-source product landing page*, not a dump of architecture notes.

Required above-the-fold composition:

```text
[Original Patchbeam icon] PATCHBEAM
From broken to verified, without breaking your flow.
[macOS badge] [Apple silicon badge] [license badge] [CI badge] [latest release badge]
[Hero animated real app crop / original screenshot]
A 2-sentence explanation of problem and unique value.
[Download latest release]  [Watch real demo]  [Build from source]
```

Then sections in this order:

1. **Why Patchbeam** — one concrete failing-test story, very short.
2. **See it work** — authentic hero loop, 45–90 second linked video, timestamped steps.
3. **What makes it different** — From Error / Isolated Agent / Real Proof / You Decide four-panel illustrated flow; assets drawn from actual UI or purpose-made diagrams.
4. **Quick start (under 3 minutes on supported machine)** — clearly distinguish prebuilt signed release vs developer build; no false promises without a published release.
5. **System requirements** — actual tested macOS version and chip, notch not strictly required, supported providers and version minima, Git and Python fixture dependency.
6. **Installation** — Release DMG instructions (open DMG → drag into Applications → launch), checksum and signature verification; optional Homebrew only after a real cask exists; source commands actually tested.
7. **First fix tutorial** — use bundled `broken-python` fixture, including commands to see failure and create capsule; screenshots from real app.
8. **Keyboard shortcuts** — in table; customizable and conflicts documented.
9. **Privacy and safety** — worktree ≠ sandbox; selected context sent to provider; user confirms consequential changes.
10. **Provider support** — actual compatibility status table with capability flags (`Run`, `Stream`, `Approve`, `Resume`) and tested versions; no aspirational checkmarks.
11. **Architecture (one readable diagram)** — SwiftUI panel → capsule orchestration → Git worktree + provider → host verifier → review; accessible alt text.
12. **Building/testing from source** — exact commands, Xcode prerequisites, test setup and troubleshooting.
13. **FAQ** — no notch? provider costs? can I use Cursor? how to remove data? permissions? offline demo? why no auto-merge?
14. **Contributing, security reporting, license, acknowledgments** — short links to complete docs.

README should use a restrained dark palette in images; GitHub Markdown itself can't be completely custom themed. Avoid giant centered HTML tables, unrenderable video embeds, auto-playing sound, excessive emoji, stock screenshots, broken badge URLs, and mock data represented as real usage. Add **alt text** to all images.

# 20. Packaging, distribution, and update strategy

**Supported and honest release paths:**

- **Development:** `xcodebuild` or `scripts/build.sh` on a Mac with documented Xcode toolchain, then open local `.app`.
- **Public recommended:** Developer ID-signed **hardened runtime**, Apple-notarized, stapled `.dmg`, plus SHA-256 release checksum and verification commands. Verify with `codesign`, `spctl`, and `xcrun stapler validate` and record results.
- **No Apple Developer credentials:** publish source build and, if a preview app is produced, label it **unsigned/unnotarized preview**. Do not claim one-click trusted install or advise disabling Gatekeeper globally. Keep instructions for safely using local builds.
- **CI release:** GitHub Actions with protected signing credentials. Dry-run builds use no private certs; release job signs only in protected context and only when secrets exist. No secret values in logs.
- **Updates:** v1 may offer `Check GitHub Releases` with an external link. Sparkle or another update mechanism is P1 only after code signing, secure update-key management, and tested rollback. Do not ship an insecure updater for convenience.
- **Homebrew:** only add cask/tap instructions once a real, downloadable version and hash exist; never print an unverified `brew install ...` command.

**Release assets:** `Patchbeam-<version>-arm64.dmg` (only if built), checksums, clear release notes, actual demo media, licensing/known issues and verified installation steps. Optional universal binary only after actual Intel tests and supporting build.

# 21. CI, quality gates, and release report

Every PR pipeline should report the exact workflow steps; do not hide status behind a decorative badge. Use pinned actions and explicit minimal permissions. Generate test result bundles and capture crash reports when feasible. Set hard failure on compiler warnings that indicate data races or test regressions, but do not let optional unavailable simulator/GUI infrastructure block core tests silently: separate jobs and clearly mark skipped/unsupported.

`docs/QUALITY_REPORT.md` must be generated/updated from actual evidence and include:

- Commit SHA, build artifact hash, date, host Mac model (or VM label), macOS, architecture and Xcode versions.
- Test count, pass/fail/skip, commands, durations, and reference to CI logs or `.xcresult` artifacts.
- Actual provider integration probe, version and full live golden-path verdict (with secrets removed).
- Hardware notch UI verdict, external monitor/fullscreen verdict, keyboard/accessibility verdict.
- Idle CPU and memory measures on named reference system, plus UI responsiveness observation.
- Signing/notarization status and installation clean-user walkthrough.
- Media file existence, length, thumbnail, and review outcome.
- **Known limitations**, blocked gates and exact remaining work. A feature is either built and verified, built but unverified, or not built. Never mark the entire product “complete” from unit tests alone.

# 22. Accessibility and small-display UX acceptance

- VoiceOver names for `Open Patchbeam`, `Running repair for <repo>`, `Stop agent`, `Run verification`, `Apply patch`, `Deny request`.
- Every status includes a word/icon, not solely red/green.
- No text smaller than practical macOS interface readability in expanded views; zoom/text-scale tests.
- Focus order goes header → content/tabs → actions; `Escape` dismisses only the frontmost transient state and must not unexpectedly cancel an active agent.
- Reduced Motion removes positional/spring effects; high contrast increases separation; reduced transparency avoids low-contrast glass.
- Drag/drop functionality has full keyboard alternative.
- Verify with display scaling, long repository names, RTL/Unicode strings and giant file paths; use tooltips + truncation rather than resizing outside screen.

# 23. Edge-case and failure copy requirements

| Condition | User-visible behavior | Safe recovery |
|---|---|---|
| CLI missing | “Install a supported coding agent to run a real repair.” | Show instructions; DemoAgent remains available. |
| CLI not authenticated | “Sign in with your provider CLI first.” | Open provider docs/terminal, retry probe. |
| No Git repository | “Choose a folder containing a Git repository.” | Folder picker; no init without consent. |
| Dirty active tree | “Your uncommitted edits are not in this repair worktree.” | Cancel or proceed from HEAD. |
| Agent stuck | “No agent update for X minutes.” | View logs, stop, wait; don't falsely declare dead. |
| Agent denied permission | “Agent couldn't complete this step.” | Review requested scope, reattempt if safe. |
| Test failed | “Check failed (exit 1). Changes are available to review.” | Open proof, retry once, stop. |
| Test passed but patch changed | “Previous checks no longer match these files.” | Re-run verification. |
| Destination changed since start | “Your branch has changed; automatic apply is paused.” | Open worktree, manual merge, no overwrite. |
| App crashed | “Previous repair was interrupted; its worktree is preserved.” | Reconcile/inspect/retry. |
| Display disappeared | Capsule moves to another display safely. | Reset display preference. |
| Disk space low | Stop before worktree or logging exceeds budget; show precise error. | Free space, clear old capsules with consent. |
| Permission unavailable in provider | “Approve this action in [provider] terminal.” | Focus owner app, no spoofed allow. |

# 24. The implementation sequence (for an autonomous coding agent)

**Gate 0 — Audit prerequisites and risks.** Read whole PRD, verify host and toolchain, decide provider integration based on actual protocol documentation and installed tools, identify signing limitations; save plan in `docs/BUILD_PLAN.md` with verifiable milestones. Do not silently lower acceptance criteria.

**Gate 1 — Native shell.** Build actual app, menu bar/settings, borderless notch panel, geometry engine, collapsed/glance/expanded UI, motion/keyboard handling. Add geometry unit tests. Capture one real screenshot if GUI available.

**Gate 2 — Domain and fixture.** Implement capsule model, SQLite/state machine, diagnostic intake, repo selection, fixture Git integration, and deterministic DemoAgent. Verify red→green `unittest` proof and source-repo immutability.

**Gate 3 — Real provider.** Implement one provider using documented protocol. Run live integration when authenticated/allowed; explicitly mark unavailable otherwise. No dummy responses. Approval and cancellation behavior must match protocol capabilities.

**Gate 4 — Review/apply and hardening.** Diff/verification, safe manual apply, persistence/recovery, redaction, hostile-path and concurrency tests, polished errors.

**Gate 5 — UX refinement.** Run UI and accessibility review, interaction tests, display/focus checks, reduced motion, animations and performance profiling; fix actual usability issues rather than merely adding visual effects.

**Gate 6 — Documentation/media/package.** Make README a polished landing page, package artifacts with correct signing labels, run clean install, record and inspect authentic videos and screenshots, verify links and docs.

**Gate 7 — Final audit.** Run all reproducible commands from scratch. Update quality report. Fix blockers and re-test. Report exactly what works, what wasn't tested, and what requires host permissions or signing. Do not say the app is production-ready without the release gates.

**Quality rule:** Don't stop at implementation. For each gate: **build → test → observe → fix → re-test → evidence → next gate**. Favor completeness over feature count. Maintain coherent small commits and useful messages; do not touch unrelated user repositories.

# 25. Final release acceptance checklist

## Core product

- [ ] A real compiled macOS SwiftUI/AppKit app launches without a browser/web backend.
- [ ] Physical-notch geometry tested on at least one actual supported notched Mac, or explicitly blocked/not claimed.
- [ ] Correct non-notch/external display fallback and panel bounds.
- [ ] Real keyboard, hover/click, focus, animation and accessibility behavior.
- [ ] Fully functional diagnostic paste/drop + repository selection.
- [ ] Actual Git worktree, base commit capture and dirty-state warning.
- [ ] One working live provider adapter, with honest capabilities; demo adapter separately labeled.
- [ ] Real events, clear approvals, cancellation, and error paths.
- [ ] Verification command actually runs and retains exit code/logs/fingerprint.
- [ ] Diff review, open in editor, safe apply/conflict detection and discard controls.
- [ ] No silent user-project mutations, commits, pushes, or permission bypass.
- [ ] App restart/recovery and old capsule retention.

## Verification

- [ ] Deterministic red→green fixture run passes from pristine environment.
- [ ] No model output can forge verified state.
- [ ] Adversarial Git, injection, process, stale-approval and crash tests pass.
- [ ] Build/test scripts pass on documented macOS toolchain.
- [ ] UI test suite and hardware manual checks have recorded results.
- [ ] Real-provider flow tested or explicitly listed as release blocker.

## Shipping

- [ ] README has authentic screenshot/hero loop and working install instructions.
- [ ] 45–90 second demo shows a real start-to-finish repair.
- [ ] Real-provider clip exists if its integration is claimed and testable.
- [ ] All links, binary paths, video playback, image alt text, README commands validated.
- [ ] DMG is signed/notarized and verified **if advertised as trusted public release**.
- [ ] Checksums, license, changelog, security policy, privacy docs, troubleshooting present.
- [ ] `QUALITY_REPORT.md` clearly separates passed/failed/unverified.
- [ ] Fresh machine/user or VM install proven; actual hardware-notch test separately proven.

# 26. Explicit anti-patterns and prohibited shortcuts

- Do not fake a status feed using timers; actual provider events or a clearly labeled scripted DemoAgent only.
- Do not put decorative mock media into the final README in place of real recordings.
- Do not use an Electron app simply because it is easier to style; native AppKit/SwiftUI is an architectural requirement.
- Do not call any code “verified” based on an LLM completion message.
- Do not swallow nonzero process or CI exit codes.
- Do not use `shell: true` style command execution for user-provided arbitrary strings.
- Do not describe worktrees as a process or network sandbox.
- Do not edit the developer's source worktree as a side effect of agent execution.
- Do not automatically open a GitHub PR, `git push`, `git reset --hard`, force merge, or delete a non-app-owned path.
- Do not rely on private macOS APIs when documented public mechanisms suffice; if an effect requires private APIs, drop the effect and record that decision.
- Do not install paid software, sign into provider accounts, change system privacy controls, or take screen recordings without the user's authorization.
- Do not insert fake code-signing badges, nonexistent Homebrew formulae, or links to unbuilt releases.
- Do not silently substitute mocked UI tests for actual macOS hardware tests.

# 27. Risk register / design decisions

| Risk | Severity | Decision |
|---|---|---|
| Existing notch agents offer overlapping monitoring/approval | High for differentiation | Own diagnostic-to-proof flow; no general-purpose widget arms race. |
| Provider protocols shift | High | Adapter capability negotiation, version pinning, contract fixtures, precise support matrix. |
| Agent terminal execution harms user environment | Critical | Scoped runs, explicit approval, minimal permissions, clear worktree caveat; isolate further in future VM feature. |
| macOS full-screen/notch placement unreliable | High | AppKit geometry abstraction and fallback pill; actual device tests mandatory. |
| AI succeeds on fixture but fails generally | High | Demonstrate fixture and real run separately, truthful proof semantics. |
| Notarization credentials not available | Medium | Source-first development; unsigned clearly labeled preview; public trusted release blocked. |
| README video / media spoofed or broken | Medium | Record real frames, verify playback and links, preserve source evidence. |
| Overbuilding | Critical to one-shot success | P0 vertical slice first; P1/P2 only after gates. |
| Name unavailable | Low/medium | Patchbeam is provisional until clearance. |

# 28. Final expected handoff to product owner

The implementation agent must return these, with links/paths that really exist:

1. **Git repository** with native source, documentation, tests, fixtures, actual history and license.
2. **Runnable app** built on an actual Mac, plus signed/notarized public distribution if credentials and permissions enable it (otherwise exact blocker).
3. **README** that feels like a top-tier developer tool landing page, with authentic UI evidence and direct Quick Start.
4. **One-page verification report** listing each major requirement as Passed / Failed / Not Tested, with commands and links to evidence.
5. **Authentic screen recordings and optimized hero loop**, or explicit honest blockers if capture unavailable.
6. **Unambiguous first-user experience:** install → launch → run bundled local demo → connect an installed provider → fix a real local test with reviewable evidence.
7. **Release-readiness verdict** that does not claim untested hardware, signing or provider features.

**Definition of a good v1:** One delighted developer can install Patchbeam, run a real fix, trust the evidence, and get back to their editor, while the app feels so native and unobtrusive that the notch is the natural place for the workflow.

---

# 29. Primary research and technical references

Accessed/checked for this specification on **11 November 2026**. Product features and prices can change; recheck during implementation and do not copy competitor code or art.

### Product landscape

- NotchNook official Classic/Pro description: https://lo.cafe/notchnook/ ; official Pro description: https://getnotchnook.com/ ; changelog: https://getnotchnook.com/changelog
- Boring Notch source and README (GPL-3.0): https://github.com/TheBoredTeam/boring.notch
- Super Notch session manager: https://www.supernotch.ai/
- Agent Notch source: https://github.com/Aforno/AgentNotch
- Kannu source: https://github.com/libinmv/kannu
- Notchy agent approvals/usage features: https://notchy.dev/
- NotchIA source: https://github.com/coaxel2/NotchIA
- Padu worktree/checkpoint product: https://padu.dev/
- Mac notch competitor overview (vendor-authored, treat claims/pricing as self-reported): https://notchdesk.com/blog/notchnook-alternatives ; https://www.supernotch.ai/alternatives/notch-apps

### Authoritative engineering references

- Apple `NSScreen` geometry/safe area/auxiliary top areas: https://developer.apple.com/documentation/AppKit/NSScreen
- Apple `NSWindow.CollectionBehavior`: https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct
- Apple Xcode testing: https://developer.apple.com/documentation/xcode/testing
- Apple ScreenCaptureKit and consent: https://developer.apple.com/documentation/screencapturekit
- Apple Virtualization for macOS guests on Apple silicon: https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon
- Apple Developer ID and notarization: https://developer.apple.com/developer-id/ ; https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- OpenAI Codex official platform/app-server guidance: https://developers.openai.com/blog/codex-as-a-platform
- Anthropic Claude Code hook patterns: https://support.claude.com/en/articles/14554000-claude-code-power-user-tips ; https://claude.com/blog/how-to-configure-hooks

**Research caution:** Vendor feature matrices are self-reported, and competitor behavior should not be asserted beyond official descriptions without direct hands-on verification. This PRD specifies a *new build*, not an existing verified application.
