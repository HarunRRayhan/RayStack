#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

REQUIRED=(raystack aws-billing-review aws-security-review aws-bottleneck-review infra-review scaling-review database-review)

for s in "${REQUIRED[@]}"; do
  [ -f "skills/$s/SKILL.md" ] || fail "missing skill $s"
done

# Print a frontmatter field (text between the first two --- lines).
fm() {
  awk -v k="$2" '
    /^---[[:space:]]*$/ { n++; next }
    n == 1 && index($0, k ":") == 1 { sub("^" k ":[[:space:]]*", ""); print; exit }
    n >= 2 { exit }
  ' "$1"
}

for f in skills/*/SKILL.md; do
  [ -e "$f" ] || continue
  dir=$(basename "$(dirname "$f")")
  assert_eq "$(fm "$f" name)" "$dir" "$f name matches directory"
  desc=$(fm "$f" description)
  if [ "${#desc}" -ge 40 ]; then pass "$f description"; else fail "$f description missing or under 40 chars"; fi
done

if [ -d skills ] && grep -rl '—' skills >/dev/null; then
  fail "em-dash found in: $(grep -rl '—' skills | tr '\n' ' ')"
else
  pass "no em-dashes in skills/"
fi
exit "$FAILED"
