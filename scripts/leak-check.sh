#!/usr/bin/env bash
# Fail if any deny-list term appears in a tracked file. Usage: leak-check.sh [denylist-file]
# Terms come from the file (one per line) or $RAYSTACK_DENYLIST (newline-separated).
# Blank lines and '#' lines are ignored. Output never prints a term (CI logs are public).
if [ -n "${1:-}" ]; then
  [ -f "$1" ] || { echo "leak-check: deny-list file not found: $1" >&2; exit 2; }
  terms="$(cat "$1")"
else
  terms="${RAYSTACK_DENYLIST:-}"
fi
if [ -z "$(printf '%s' "$terms" | tr -d '[:space:]')" ]; then
  echo "leak-check skipped: no deny-list" >&2
  exit 0
fi

# Terms are read above, so a relative deny-list path resolves before this cd.
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "leak-check: not a git repo" >&2; exit 2; }
cd "$root" || exit 2

hits=0
n=0
while IFS= read -r term || [ -n "$term" ]; do
  term="${term%$'\r'}"
  term="${term#"${term%%[![:space:]]*}"}"  # trim leading whitespace
  term="${term%"${term##*[![:space:]]}"}"  # trim trailing whitespace
  case "$term" in ''|'#'*) continue ;; esac
  n=$((n + 1))
  # -I skips binaries; keep file:line only (cut drops the matching text)
  out="$(git grep -I -i -n -F -e "$term" 2>/dev/null)"
  rc=$?
  if [ "$rc" -ge 2 ]; then echo "leak-check: git grep failed (rc $rc)" >&2; exit 2; fi
  found="$(printf '%s' "$out" | cut -d: -f1,2)"
  if [ -n "$found" ]; then
    hits=$((hits + 1))
    while IFS= read -r loc; do echo "leak: $loc (term #$n)"; done <<< "$found"
  fi
done <<< "$terms"

if [ "$hits" -gt 0 ]; then
  echo "leak-check FAILED: $hits term(s) found" >&2
  exit 1
fi
echo "leak-check ok ($n terms)"
