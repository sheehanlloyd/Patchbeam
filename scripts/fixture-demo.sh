#!/usr/bin/env bash
# Deterministic red→green repair of the bundled broken-python fixture, using the scripted
# DemoAgent (no model). Runs entirely in a fresh temp directory; never touches your repos.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != "--headless" ]]; then
  echo "usage: $0 --headless [--scenario fix|wrongFixThenFix|approval] [--keep]" >&2
  exit 2
fi
swift build --product patchbeam-cli >/dev/null
exec .build/debug/patchbeam-cli demo "$@"
