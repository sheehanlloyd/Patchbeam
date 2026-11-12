# Claude Code stream-json contract fixtures

| File | Origin |
|---|---|
| `unauthenticated-2.1.252.jsonl` | **Captured** from Claude Code 2.1.252 on 2026-11-11, run with Patchbeam's exact scoped argv in a scratch directory. The standalone CLI was not logged in. Paths, session IDs and the memory/socket paths are redacted. |
| `unauthenticated-2.1.322.jsonl` | **Captured** the same way from Claude Code 2.1.322 on 2026-11-12, after the CLI auto-updated. Same scoped argv accepted; same `authentication_failed` shape. |
| `documented-shape-success.jsonl` | **Constructed** by hand from the documented Agent SDK message types (`system/init`, `assistant` with `text`/`tool_use` blocks, `user` with `tool_result`, `result`). It also includes a duplicate message, a malformed line and a `stream_event`, to exercise dedupe and robustness. Replace it with a captured stream once a logged-in run is available. |
