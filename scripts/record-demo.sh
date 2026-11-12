#!/usr/bin/env bash
# Records authentic media from the REAL app: builds Patchbeam.app, runs `--autodemo` on a fresh
# fixture in an isolated data dir, captures the app's own panel window (no desktop, no Screen
# Recording permission), adds state-derived captions, and encodes:
#   docs/media/Patchbeam-Demo.mp4   real-time walkthrough
#   docs/media/hero.gif             short loop, visibly labeled when sped up
#   docs/media/*.png                stills
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null || { echo "ffmpeg is required for media encoding" >&2; exit 1; }
pace="${PACE:-2.8}"
# LIVE=1 records a run with the real Claude Code provider (must be signed in; spends a few cents).
live="${LIVE:-0}"
if [[ "$live" == 1 ]]; then
  flag="--autodemo-live"
  claude_version="$(claude --version 2>/dev/null | awk '{print $1}')"
  agent_label="Claude Code ${claude_version} (real model, live)"
else
  flag="--autodemo"
  agent_label="scripted DemoAgent (no model)"
fi
work="$(mktemp -d "${TMPDIR:-/tmp}/patchbeam-media.XXXXXX")"
echo "work dir: $work"

./scripts/build.sh release >/dev/null
pkill -x Patchbeam 2>/dev/null || true
sleep 1
open -W --env PATCHBEAM_HOME="$work/home" --env PATCHBEAM_CAPTURE_DIR="$work/capture" \
     --env PATCHBEAM_AUTODEMO_PACE="$pace" --stderr "$work/autodemo.log" \
     build/Release/Patchbeam.app --args "$flag" --quit-after
grep -q "autodemo: done status=applied" "$work/autodemo.log" || { echo "autodemo did not reach 'applied':" >&2; cat "$work/autodemo.log" >&2; exit 1; }

mkdir -p docs/media
swift scripts/compose-media.swift "$work/capture" "$work/composed" "real time" "$agent_label" >/dev/null
if [[ "$live" == 1 ]]; then
  ffmpeg -y -loglevel error -framerate 12 -i "$work/composed/c-%05d.png" \
    -c:v libx264 -pix_fmt yuv420p -preset slow -crf 20 -movflags +faststart -r 30 docs/media/Patchbeam-Agent-Run.mp4
  for s in 05-running 08-review-proof; do cp "$work/capture/still-$s.png" "docs/media/live-$s.png"; done
  cp "$work/autodemo.log" docs/media/autodemo-live.log
  ffprobe -v error -show_entries format=duration -of csv=p=0 docs/media/Patchbeam-Agent-Run.mp4 | xargs printf 'Patchbeam-Agent-Run.mp4: %.1fs\n'
  exit 0
fi
ffmpeg -y -loglevel error -framerate 12 -i "$work/composed/c-%05d.png" \
  -c:v libx264 -pix_fmt yuv420p -preset slow -crf 20 -movflags +faststart -r 30 docs/media/Patchbeam-Demo.mp4

# Hero loop: from intake onward, every 5th captured frame (= 5x speed, labeled on every frame).
mkdir -p "$work/hero"
start="$(awk -F'\t' '$3 == "intake" { print $1; exit }' "$work/capture/frames.tsv")"
awk -F'\t' -v s="$start" 'BEGIN{OFS="\t"} $1 >= s && ($1 - s) % 5 == 0 { print }' "$work/capture/frames.tsv" > "$work/hero/src.tsv"
i=0
: > "$work/hero/frames.tsv"
while IFS=$'\t' read -r idx rest; do
  cp "$work/capture/$(printf 'frame-%05d.png' "$idx")" "$work/hero/$(printf 'frame-%05d.png' "$i")"
  printf '%s\t%s\n' "$i" "$rest" >> "$work/hero/frames.tsv"
  i=$((i+1))
done < "$work/hero/src.tsv"
swift scripts/compose-media.swift "$work/hero" "$work/hero-composed" "5× speed" >/dev/null
ffmpeg -y -loglevel error -framerate 12 -i "$work/hero-composed/c-%05d.png" \
  -vf "scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a" \
  -loop 0 docs/media/hero.gif

# Chapter timestamps for the README, from the recorded state of each frame (12 fps).
awk -F'\t' '
  { key = $3 "/" $4 "/" $7 "/" $8 }
  key != last { printf "%5.1fs  %-9s %-22s %-8s %s\n", $1/12, $3, $4, $7, $8; last = key }
' "$work/capture/frames.tsv" > docs/media/chapters.txt

for s in 03-intake-demo 05-running 07-review-changes 08-review-proof 09-apply-confirm 10-applied; do
  [[ -f "$work/capture/still-$s.png" ]] && cp "$work/capture/still-$s.png" "docs/media/$s.png"
done
cp "$work/capture/geometry.log" docs/media/geometry-evidence.log
cp "$work/autodemo.log" docs/media/autodemo.log
ffprobe -v error -show_entries format=duration -of csv=p=0 docs/media/Patchbeam-Demo.mp4 | xargs printf 'Patchbeam-Demo.mp4: %.1fs\n'
ffprobe -v error -show_entries format=duration -of csv=p=0 docs/media/hero.gif | xargs printf 'hero.gif: %.1fs\n'
ls -lh docs/media
