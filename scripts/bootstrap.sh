#!/usr/bin/env bash
# Checks prerequisites. Installs nothing and changes no global configuration.
set -euo pipefail
mode="${1:---check}"
[[ "$mode" == "--check" ]] || { echo "usage: $0 --check" >&2; exit 2; }

fail=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$1"; fail=1; }

echo "Patchbeam prerequisites"
[[ "$(uname -s)" == "Darwin" ]] && ok "macOS $(sw_vers -productVersion) ($(uname -m))" || bad "Patchbeam builds only on macOS"
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 15 )) && ok "macOS 15 or newer" || bad "macOS 15+ required (found $(sw_vers -productVersion))"
if xcrun --find swift >/dev/null 2>&1; then
  ok "$(xcrun swift --version 2>/dev/null | head -1)"
  sv="$(xcrun swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+)\..*/\1/p' | head -1)"
  [[ -n "$sv" && "$sv" -ge 6 ]] || bad "Swift 6 or newer required (install Xcode 16+)"
else
  bad "Swift toolchain missing — install Xcode or run: xcode-select --install"
fi
command -v xcodebuild >/dev/null && ok "$(xcodebuild -version 2>/dev/null | head -1)" || warn "xcodebuild not found (Command Line Tools only is fine for swift build)"
command -v git >/dev/null && ok "$(git --version)" || bad "git missing"
command -v python3 >/dev/null && ok "$(python3 --version) (fixture uses only the standard library)" || bad "python3 missing (needed for the broken-python fixture)"
if command -v claude >/dev/null; then
  ok "Claude Code $(claude --version 2>/dev/null | head -1) (optional real provider)"
else
  warn "Claude Code not found — optional; DemoAgent works without it"
fi
command -v ffmpeg >/dev/null && ok "ffmpeg (optional, media scripts)" || warn "ffmpeg not found (optional, only for media scripts)"
exit $fail
