#!/usr/bin/env bash
# Runs the full unit + integration suite. Fails on any failing test (exit code is propagated).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/test-results
swift build --build-tests 2>&1 | tee build/test-results/build.log | grep -E "error|warning:" || true
set +e
swift test --parallel --xunit-output build/test-results/results.xml 2>&1 | tee build/test-results/test.log
status=${PIPESTATUS[0]}
set -e
grep -E "Test run with [0-9]+ tests" build/test-results/test.log | tail -1 || true
exit "$status"
