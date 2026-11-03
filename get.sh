#!/usr/bin/env bash
# One-line install for any agent:
#   curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash
# Clones (or updates) RayStack in ~/.raystack, then installs it for every agent on this
# machine. Extra arguments go to install.sh, e.g. `| bash -s -- --project .`.
set -euo pipefail

main() {
  local dir="${RAYSTACK_DIR:-$HOME/.raystack}"
  command -v git >/dev/null 2>&1 || { echo "RayStack needs git. Install git, then run this again." >&2; exit 1; }
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only --quiet
  else
    git clone --quiet --depth 1 https://github.com/HarunRRayhan/RayStack.git "$dir"
  fi
  local agent=all a
  for a in "$@"; do [ "$a" != --agent ] || agent=""; done  # the caller chose an agent
  if [ -n "$agent" ]; then exec "$dir/install.sh" --agent all "$@"; else exec "$dir/install.sh" "$@"; fi
}

main "$@"  # last line, so a partial download runs nothing
