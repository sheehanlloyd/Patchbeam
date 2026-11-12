# ADR-0002: Claude Code stream-json is the first live provider

**Status:** accepted · 2026-11-11

## Context
The PRD prefers Codex app-server. On the build host, `@openai/codex` 0.93.0 is installed, but its native binary (`vendor/aarch64-apple-darwin/codex/codex`) is missing, so `codex --version` fails with `ENOENT`. Repairing it would change the user's global environment without permission. Claude Code 2.1.252 is installed and documents a headless mode (`-p --output-format stream-json --verbose`).

## Decision
Implement `ClaudeCodeAdapter` against the **installed** CLI:
- argv: `-p --output-format stream-json --verbose --tools Read,Edit,Write --allowedTools Read,Edit,Write --permission-mode acceptEdits --restricted --strict-mcp-config --setting-sources "" --no-session-persistence --max-budget-usd <cap>`
- The prompt goes over stdin. The cwd is the app-owned worktree. The environment is minimal. The process runs in its own process group (Stop = SIGTERM, then SIGKILL, to that group).
- The CLI's `system/init` line confirmed this argv on the real install: tools `Edit,Read,Write`, `permissionMode: acceptEdits`, no MCP servers.
- Approvals: Claude Code exposes host approval only through an MCP `--permission-prompt-tool`, which v1 doesn't implement. So `capabilities.approve = false`, `respond()` throws, the UI shows "Approve this action in Claude Code's terminal," and there is no Allow button.
- The agent has no shell tool. **Patchbeam runs verification itself.**

## Consequences
- A live run needs `claude auth login`. Before sign-in the CLI reported `loggedIn: false`, and that real stream (`authentication_failed`) is a contract test on 2.1.252 and 2.1.322.
- After sign-in (2026-11-12), a live repair succeeded on 2.1.322. Its redacted stream (`success-2.1.322.jsonl`) is now a contract test, next to the hand-built documented-shape fixture.
- A Codex adapter can be added behind the same `AgentAdapter` protocol once a working install is available.
