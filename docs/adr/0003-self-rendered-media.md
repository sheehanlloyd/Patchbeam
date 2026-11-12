# ADR-0003: Demo media is rendered by the running app itself

**Status:** accepted · 2026-11-12

## Context
The PRD requires authentic recordings of the real app. On the build host, `screencapture` fails ("could not create image from display") because the host process lacks Screen Recording permission. The computer-use tooling can't target LSUIElement (menu-bar agent) apps. Changing macOS privacy settings on the user's behalf isn't allowed.

## Decision
When `PATCHBEAM_CAPTURE_DIR` is set, `EvidenceRecorder` renders **only Patchbeam's own panel window** (`NSView.cacheDisplay`) to PNG frames, together with a `frames.tsv` of the real app state for each frame and a `geometry.log` comparing the panel frame with the notch the OS reports. `--autodemo` drives the golden path through the same `AppModel` methods the buttons call. `scripts/compose-media.swift` adds captions taken from the recorded state and a permanent disclosure line ("Real Patchbeam app · scripted DemoAgent (no model) · app's own panel window, no desktop · real time / 3× speed").

## Consequences
- The media is real UI from a real run (real Git, real `unittest`, real apply), but it **does not show the desktop, menu bar or camera housing**. Physical notch fit is evidenced numerically in `docs/media/geometry-evidence.log`, not visually.
- Clicks are issued programmatically through the model, not by a pointer. The media doesn't claim otherwise.
- A full-desktop recording requires the user to grant Screen Recording to their terminal and run `scripts/record-desktop.sh` (see RELEASE_CHECKLIST).
