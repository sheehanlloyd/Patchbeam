# Security model

## Trust model
- **Pasted logs are untrusted.** They can contain secrets, prompt injection, escape sequences or huge payloads. Patchbeam strips ANSI/OSC/C1/bidi controls, caps size (keeping head and tail), flags likely secrets for one-click redaction, and passes the text to the agent inside a fenced `<diagnostic>` block marked as untrusted data.
- **Repositories are untrusted.** Every Git call passes `-c core.hooksPath=/dev/null -c core.fsmonitor=false` (plus `--no-ext-diff --no-textconv` for diffs), so no repository-controlled code runs during inspection, worktree creation, diffing or apply.
- **Check commands run repository code.** The user must approve the exact argv. Approval is cleared whenever the command changes. It runs without a shell, in the worktree, with a minimal environment, a timeout and capped output.
- **A worktree is not a sandbox.** It isolates Git checkout state only. The agent's own runtime (Claude Code) can read other files or use the network under its own policy. Patchbeam narrows that policy (`--tools Read,Edit,Write`, `--restricted`, no MCP, no settings sources) but can't enforce it.

## Threats and mitigations (PRD §14.3)

| Threat | Mitigation in this build | Residual risk |
|---|---|---|
| Prompt injection in logs/repo | Fenced untrusted diagnostic; no shell tool for the agent; host-owned verification | The model may still be misled into a bad edit; you review the diff |
| Malicious check script | Explicit approval of exact argv; no shell; timeout; process group kill | The script has your user's permissions |
| Secret leakage | Local scanner + Redact button; minimal env (no `ANTHROPIC_*` or other vars forwarded); `.env` and ignored files aren't in the worktree | Git-tracked secrets are in the worktree; scanner is fallible |
| Symlink/path escape | `realpath`-based containment before creating/removing worktrees and resolving check executables | TOCTOU between check and use |
| Patch applied over user edits | HEAD must equal base; touched paths must be clean; `git apply --check`; working tree only; reverse-check after | Manual merge may be needed |
| Approval race / replay | One pending request; responses only while pending; expiry auto-denies; replay throws `approvalStale` | Provider semantics vary |
| Fake success | `reviewReadyVerified` requires a passing host verification for the exact patch fingerprint | Passing tests don't prove correctness |
| Supply chain | No third-party Swift packages; system SQLite; CI actions pinned by SHA | Unsigned preview builds aren't notarized |

## Not implemented in v1
Local IPC/socket (no terminal helper yet), screenshot/OCR intake, telemetry, auto-update. None of these attack surfaces exist in this build.
