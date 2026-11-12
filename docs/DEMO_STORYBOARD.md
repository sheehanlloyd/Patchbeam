# Demo storyboard

The recorded media follows this storyboard. Every frame comes from the running app (see [ADR-0003](adr/0003-self-rendered-media.md)).

| # | Beat | What's on screen | Source of truth |
|---|---|---|---|
| 1 | Dormant | Black island the width of the notch (197×32 pt around a 185×32 pt housing) | `geometry-evidence.log` |
| 2 | Glance | “What broke? ⌃⌥Space” | Real panel |
| 3 | Intake | Fixture traceback (17 lines · 788 bytes), fresh fixture repo `main @ <sha>`, DemoAgent with “Demo — no model used”, check `python3 -m unittest -v` | Real fixture repo created at run time |
| 4 | Approve check | Checkbox approving the exact argv | `IntakeState.checkApproved` |
| 5 | Running | Worktree created → baseline exit 1 → DemoAgent reads, edits `calculator.py` | Real events from the orchestrator |
| 6 | Review: Changes | Git diff `- base - tax` / `+ base + tax`, 1 file · +1 −1 | `git diff` via throwaway index |
| 7 | Review: Proof | After: exit 0, 3 tests ran · 3 passed. Before: exit 1, 2 passed · 1 failed | `VerificationRecord`s |
| 8 | Apply confirm | Working tree only; nothing staged, committed or pushed | `ApplyService` preconditions |
| 9 | Applied | “Applied to your working tree” | Source repo passes `unittest` afterwards (asserted in CLI demo) |
| 10 | Back to notch | Glance shows the finished capsule | Real panel |

**Not shown, and not claimed:** the macOS desktop and menu bar around the panel, a pointer clicking (the run is driven through the app model), and a real LLM provider (the live Claude Code clip is blocked until `claude auth login`).
