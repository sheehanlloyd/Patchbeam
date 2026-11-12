#!/usr/bin/env bash
# Fails if a relative link or image in the Markdown docs points to a file that doesn't exist.
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
while IFS= read -r file; do
  dir="$(dirname "$file")"
  while IFS= read -r target; do
    target="${target%%#*}"
    [[ -z "$target" || "$target" =~ ^(https?:|mailto:) ]] && continue
    if [[ ! -e "$dir/$target" ]]; then
      echo "broken link in $file → $target"
      status=1
    fi
  done < <(grep -oE '\]\(([^)]+)\)' "$file" | sed -E 's/^\]\(([^ )]+).*/\1/' || true)
done < <(git ls-files '*.md')
[[ $status -eq 0 ]] && echo "All relative Markdown links resolve."
exit $status
