#!/usr/bin/env bash
# Optional: records the WHOLE main display while the app runs --autodemo, to show the panel in
# context around the physical notch. Requires that YOU grant Screen Recording to the terminal app
# running this script (System Settings → Privacy & Security → Screen Recording). Patchbeam never
# requests this permission itself. Close private windows first; the recording shows your desktop.
set -euo pipefail
cd "$(dirname "$0")/.."
seconds="${1:-75}"
out="${2:-build/media/Patchbeam-desktop-raw.mov}"
mkdir -p "$(dirname "$out")"
if ! screencapture -x -t png "$(mktemp -t pbprobe).png" 2>/dev/null; then
  echo "Screen Recording permission is not granted to this terminal. Grant it, then re-run." >&2
  exit 1
fi
./scripts/build.sh release >/dev/null
work="$(mktemp -d)"
screencapture -v -V "$seconds" -x "$out" &
rec=$!
sleep 2
open -W --env PATCHBEAM_HOME="$work/home" --env PATCHBEAM_AUTODEMO_PACE=2.8 build/Release/Patchbeam.app --args --autodemo --quit-after
wait $rec || true
echo "Raw recording: $out (review and redact before publishing; crop with ffmpeg -vf crop=...)"
