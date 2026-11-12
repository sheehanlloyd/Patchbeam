# Contributing

Thanks for helping make Patchbeam better. The bar is **one reliable golden path** over many half-working features (see [docs/PRD.md](docs/PRD.md) §0).

## Setup
```bash
./scripts/bootstrap.sh --check   # verifies macOS 15+, Swift 6, git, python3; installs nothing
./scripts/test.sh                # full unit + integration suite
./scripts/fixture-demo.sh --headless
./scripts/build.sh debug && open build/Debug/Patchbeam.app
```
Use `PATCHBEAM_HOME=/tmp/pb-dev` to keep development data out of your real Application Support folder.

## Rules
- Core logic goes in `PatchbeamCore`, which has no SwiftUI/AppKit imports and needs tests. The app target only reflects state and forwards intent.
- Run subprocesses with `ProcessRunner` and an argv array only. Never use `sh -c` with user-supplied strings.
- Git calls go through `GitClient`, which disables hooks and fsmonitor.
- Never set “verified” from anything except a host verification record tied to the patch fingerprint.
- Use the copy in PRD §23 for user-facing errors. Never ship a bare “Unknown error.”
- Tests must not touch real user repositories. Use `TempRepo` or `FixtureLibrary`.
- Keep commits small, with messages that say *why*.

## Pull requests
CI (`.github/workflows/ci.yml`) must pass: tests, the three headless fixture scenarios, the app bundle build, and the docs link check. Include screenshots or `--autodemo` frames for UI changes.
