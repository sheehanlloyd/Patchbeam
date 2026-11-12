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
work="$(mktemp -d "${TMPDIR:-/tmp}/patchbeam-media.XXXXXX")"
echo "work dir: $work"

./scripts/build.sh release >/dev/null
pkill -x Patchbeam 2>/dev/null || true
sleep 1
open -W --env PATCHBEAM_HOME="$work/home" --env PATCHBEAM_CAPTURE_DIR="$work/capture" \
     --env PATCHBEAM_AUTODEMO_PACE="$pace" --stderr "$work/autodemo.log" \
     build/Release/Patchbeam.app --args --autodemo --quit-after
grep -q "autodemo: done status=applied" "$work/autodemo.log" || { echo "autodemo did not reach 'applied':" >&2; cat "$work/autodemo.log" >&2; exit 1; }

mkdir -p docs/media
swift scripts/compose-media.swift "$work/capture" "$work/composed" "real time" >/dev/null
ffmpeg -y -loglevel error -framerate 12 -i "$work/composed/c-%05d.png" \
  -c:v libx264 -pix_fmt yuv420p -preset slow -crf 20 -movflags +faststart -r 30 docs/media/Patchbeam-Demo.mp4

# Hero loop: the same captured frames at 3x speed, labeled as such.
mkdir -p "$work/hero"
i=0; for f in $(ls "$work/capture"/frame-*.png | awk 'NR % 3 == 1'); do cp "$f" "$work/hero/$(printf 'frame-%05d.png' $i)"; i=$((i+1)); done
awk -F'\t' 'NR % 3 == 1 { $1 = int((NR-1)/3); print }' OFS='\t' "$work/capture/frames.tsv" > "$work/hero/frames.tsv"
swift scripts/compose-media.swift "$work/hero" "$work/hero-composed" "3× speed" >/dev/null
ffmpeg -y -loglevel error -framerate 12 -i "$work/hero-composed/c-%05d.png" \
  -vf "scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a" \
  -loop 0 docs/media/hero.gif

for s in 03-intake-demo 05-running 07-review-changes 08-review-proof 09-apply-confirm 10-applied; do
  [[ -f "$work/capture/still-$s.png" ]] && cp "$work/capture/still-$s.png" "docs/media/$s.png"
done
cp "$work/capture/geometry.log" docs/media/geometry-evidence.log
cp "$work/autodemo.log" docs/media/autodemo.log
ffprobe -v error -show_entries format=duration -of csv=p=0 docs/media/Patchbeam-Demo.mp4 | xargs printf 'Patchbeam-Demo.mp4: %.1fs\n'
ls -lh docs/media
