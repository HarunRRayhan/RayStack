#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

REQUIRED=(raystack aws-billing-review aws-security-review aws-bottleneck-review infra-review scaling-review database-review app-security-review aws-readonly-setup
  principle-ship principle-smallest-change principle-ask-with-question-tool principle-secrets-layout humanize blog blog-topics blog-draft blog-cover local-verify dev dev-hub)

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

# Principle skills stay short and model-invoked.
for f in skills/principle-*/SKILL.md; do
  [ -e "$f" ] || continue
  lines=$(wc -l < "$f" | tr -d ' ')
  if [ "$lines" -lt 40 ]; then pass "$f under 40 lines"; else fail "$f has $lines lines (max 39)"; fi
  case "$(fm "$f" description)" in "Apply when "*) pass "$f description starts with Apply when" ;; *) fail "$f description must start with 'Apply when'" ;; esac
  if grep -q '^disable-model-invocation:' "$f"; then fail "$f must stay model-invoked"; else pass "$f model-invoked"; fi
done

if [ -d skills ] && grep -rl '—' skills >/dev/null; then
  fail "em-dash found in: $(grep -rl '—' skills | tr '\n' ' ')"
else
  pass "no em-dashes in skills/"
fi
exit "$FAILED"
