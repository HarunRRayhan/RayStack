#!/usr/bin/env bash
# Each review skill links the shared contract, its checklist and the guard hook.
# The entry skill names all six reviews. The blog skill names the content skills.
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=/dev/null
. ./tests/lib.sh

REVIEWS=(aws-billing-review aws-security-review aws-bottleneck-review infra-review scaling-review database-review)
CONTRACT='../raystack/references/review-contract.md'
# shellcheck disable=SC2016  # literal text expected in the frontmatter
HOOK='f="${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh"; [ -x "$f" ] || { echo "RayStack review is read-only: guard missing at $f" >&2; exit 2; }; exec "$f"'

check() { # check <description> <command...>
  local d=$1; shift
  if "$@"; then pass "$d"; else fail "$d"; fi
}

check "guard hook exists" test -f skills/raystack/hooks/readonly-guard.sh

for s in "${REVIEWS[@]}"; do
  f="skills/$s/SKILL.md"
  if [ ! -f "$f" ]; then fail "missing $f"; continue; fi
  check "$s links the contract" grep -qF "$CONTRACT" "$f"
  check "$s contract path resolves" test -f "skills/$s/$CONTRACT"
  check "$s links references/checklist.md" grep -qF 'references/checklist.md' "$f"
  check "$s checklist exists" test -f "skills/$s/references/checklist.md"
  check "$s has the guard hook command" grep -qF "$HOOK" "$f"
done

entry=skills/raystack/SKILL.md
if [ -f "$entry" ]; then
  for s in "${REVIEWS[@]}"; do
    check "raystack names $s" grep -qF "$s" "$entry"
  done
else
  fail "missing $entry"
fi

# The blog entry skill names the content skills, both voice paths and the voice sections.
CONTENT=(blog-topics blog-draft humanize blog-cover)
VOICE_H2=('## Tone' '## Openings' '## Sentences' '## Never' '## Formatting' '## Closing' '## Cover footer' '## Topics and stack' '## Ideas file')
blog=skills/blog/SKILL.md
if [ -f "$blog" ]; then
  for s in "${CONTENT[@]}"; do
    check "blog names $s" grep -qF "$s" "$blog"
  done
  check "blog names repo voice path" grep -qF '.raystack/voice.md' "$blog"
  # shellcheck disable=SC2088  # literal tilde path expected in the text
  check "blog names home voice path" grep -qF '~/.raystack/voice.md' "$blog"
else
  fail "missing $blog"
fi
for v in voice-template voice-example; do
  f="skills/blog/references/$v.md"
  if [ ! -f "$f" ]; then fail "missing $f"; continue; fi
  for h in "${VOICE_H2[@]}"; do
    check "$v has $h" grep -qxF "$h" "$f"
  done
done
exit "$FAILED"
