# Instructions for coding agents working on Patchbeam

- Read `PATCHBEAM_MASTER_PRD.md` (the product spec) and `docs/ARCHITECTURE.md` first.
- Verify with `./scripts/test.sh` and `./scripts/fixture-demo.sh --headless`. Both must pass before you commit.
- For UI changes: `./scripts/build.sh debug`, then run `PATCHBEAM_HOME=$(mktemp -d) PATCHBEAM_CAPTURE_DIR=$(mktemp -d) open -W build/Debug/Patchbeam.app --args --autodemo --quit-after` and look at the `still-*.png` frames.
- Never point automation at a real user repository. Use `FixtureLibrary.makeBrokenPythonRepo` or `TempRepo`.
- Never add `sh -c`, `--dangerously-skip-permissions`, auto-commit, push or merge behavior.
- Don't mark anything as passed in `docs/QUALITY_REPORT.md` without command output to back it.
