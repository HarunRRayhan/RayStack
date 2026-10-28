#!/usr/bin/env bash
# Run every check-*.sh and test-*.sh, each in its own process.
cd "$(dirname "$0")" || exit 1
failed=()
total=0
for f in check-*.sh test-*.sh; do
  [ -e "$f" ] || continue
  total=$((total + 1))
  echo "== $f"
  bash "$f" || failed+=("$f")
done
echo
echo "$((total - ${#failed[@]}))/$total passed"
if [ "${#failed[@]}" -gt 0 ]; then
  printf 'failed: %s\n' "${failed[@]}"
  exit 1
fi
