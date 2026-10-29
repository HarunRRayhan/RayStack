#!/usr/bin/env bash
# Each review skill links the shared contract, its checklist and the guard hook.
# The entry skill names all seven reviews. The blog skill names the content skills.
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=/dev/null
. ./tests/lib.sh

REVIEWS=(aws-billing-review aws-security-review aws-bottleneck-review infra-review scaling-review database-review app-security-review)
CONTRACT='../raystack/references/review-contract.md'
# shellcheck disable=SC2016  # literal text expected in the frontmatter
HOOK='for f in "${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh" "${CLAUDE_PLUGIN_ROOT}/../raystack/hooks/readonly-guard.sh" "$HOME/.claude/skills/raystack/hooks/readonly-guard.sh"; do [ -x "$f" ] && exec "$f"; done; echo "RayStack review is read-only: guard missing" >&2; exit 2'

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

# app-security-review carries its finding bar and its code-only and audit-skip rules.
app=skills/app-security-review/SKILL.md
if [ -f "$app" ]; then
  check "app-security-review needs a concrete exploit" grep -qF 'concrete exploit' "$app"
  check "app-security-review has Worth hardening" grep -qF 'Worth hardening' "$app"
  check "app-security-review never sends requests" grep -qF 'never sends requests' "$app"
  check "app-security-review skips audits with no lockfile" grep -qF 'no lockfile' "$app"
fi

entry=skills/raystack/SKILL.md
if [ -f "$entry" ]; then
  for s in "${REVIEWS[@]}"; do
    check "raystack names $s" grep -qF "$s" "$entry"
  done
  check "raystack is 105 lines or fewer" test "$(wc -l < "$entry")" -le 105
    # shellcheck disable=SC2016  # literal backticks, not a command substitution
  check "raystack names blog" grep -qF '`blog`' "$entry"
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
# The topic and draft skills carry their safety rules.
topics=skills/blog-topics/SKILL.md
draft=skills/blog-draft/SKILL.md
if [ -f "$topics" ]; then
  check "blog-topics shows the top 10" grep -qF 'top 10' "$topics"
  check "blog-topics waits for a pick" grep -qF 'Never draft in the same turn' "$topics"
else
  fail "missing $topics"
fi
if [ -f "$draft" ]; then
  check "blog-draft links the humanize checklist" grep -qF '../humanize/references/checklist.md' "$draft"
  check "blog-draft humanize checklist resolves" test -f "skills/blog-draft/../humanize/references/checklist.md"
  check "blog-draft asks on several posts folders" grep -qF 'ask which folder' "$draft"
  check "blog-draft keeps a future date" grep -qF 'future date' "$draft"
  check "blog-draft never invents" grep -qF 'Never invent' "$draft"
  check "blog-draft names repo voice path" grep -qF '.raystack/voice.md' "$draft"
else
  fail "missing $draft"
fi
cover=skills/blog-cover/SKILL.md
if [ -f "$cover" ]; then
  check "blog-cover uses render-cover.sh" grep -qF 'scripts/render-cover.sh' "$cover"
  check "blog-cover uses the template" grep -qF 'assets/cover-template.html' "$cover"
  check "blog-cover HTML-escapes text" grep -qF 'HTML-escape' "$cover"
  check "blog-cover never uses AI images" grep -qF 'never AI' "$cover"
  check "blog-cover render script exists" test -f skills/blog-cover/scripts/render-cover.sh
  check "blog-cover template exists" test -f skills/blog-cover/assets/cover-template.html
else
  fail "missing $cover"
fi
# local-verify never touches .env, uses throwaway data, and does not fake a browser check.
lv=skills/local-verify/SKILL.md
if [ -f "$lv" ]; then
  check "local-verify never edits .env" grep -qF "Never edit, replace, back up or write \`.env\`" "$lv"
  check "local-verify uses a throwaway database" grep -qF 'throwaway' "$lv"
  check "local-verify starts nothing without a browser tool" grep -qF 'no browser tool, say so, start nothing and claim nothing' "$lv"
  check "local-verify stops only the server it started" grep -qF 'stop only the server you started' "$lv"
  check "local-verify gives every setup command the overrides" grep -qF 'Every setup command gets the overrides' "$lv"
else
  fail "missing $lv"
fi
check "principle-ship names local-verify" grep -qF 'local-verify' skills/principle-ship/SKILL.md

check "humanize names repo voice path" grep -qF '.raystack/voice.md' skills/humanize/SKILL.md
# aws-readonly-setup: deny-data policy exists, parses, and denies the data reads the skill proves
ars=skills/aws-readonly-setup
check "aws-readonly-setup links its deny policy" grep -qF 'deny-data-policy.json' "$ars/SKILL.md"
check "deny-data policy is valid JSON" jq -e '.Statement[0].Effect == "Deny"' "$ars/deny-data-policy.json"
for a in 's3:GetObject*' secretsmanager:GetSecretValue 'ssm:GetParameter*' kms:Decrypt 'rds-data:*'; do
  # shellcheck disable=SC2016  # $a is a jq variable
  check "deny-data policy denies $a" jq -e --arg a "$a" '.Statement[0].Action | index($a)' "$ars/deny-data-policy.json"
done
# dev flow: shared contract, principles and the router
dc=skills/dev/references/dev-contract.md
if [ -f "$dc" ]; then
  for h in Decisions 'IDs and EARS' Ledger Subagents Questions 'Session start'; do
    check "dev-contract has H2 $h" grep -qxF "## $h" "$dc"
  done
  for t in 'ID | Date | Decision | Status | Supersedes | How to confirm' 'never asked again' 'Superseded by' \
    todo in-progress 'done' done-with-concerns needs-context blocked WHEN 'THE SYSTEM SHALL' B-001 'inline review' 'at most 5'; do
    check "dev-contract contains: $t" grep -qF -- "$t" "$dc"
  done
else
  fail "missing $dc"
fi
dp=skills/dev/references/principles.md
if [ -f "$dp" ]; then
  check "principles has 11 numbered items" test "$(grep -cE '^[0-9]+\. ' "$dp")" -eq 11
  check "principles has a reviewer rubric" grep -qxF '## Reviewer rubric' "$dp"
else
  fail "missing $dp"
fi
dv=skills/dev/SKILL.md
if [ -f "$dv" ]; then
  for t in Quick Standard Full replan 'no PRD' ledger 'references/dev-contract.md'; do
    check "dev contains: $t" grep -qF -- "$t" "$dv"
  done
  check "dev is 120 lines or fewer" test "$(wc -l < "$dv")" -le 120
else
  fail "missing $dv"
fi
# dev-hub: skill and template assets
hv=skills/dev-hub/SKILL.md
if [ -f "$hv" ]; then
  for t in '## RayStack dev flow' 'never overwrites' '@AGENTS.md' 'git init' 'no remote' 'single-repo' 'hub mode'; do
    check "dev-hub contains: $t" grep -qF -- "$t" "$hv"
  done
  check "dev-hub is 120 lines or fewer" test "$(wc -l < "$hv")" -le 120
  check "dev-hub contract path resolves" test -f "skills/dev-hub/../dev/references/dev-contract.md"
  check "dev-hub links the contract" grep -qF '../dev/references/dev-contract.md' "$hv"
else
  fail "missing $hv"
fi
for a in AGENTS.md DECISIONS.md AGENTS-pointer.md; do
  [ -f "skills/dev-hub/assets/$a" ] || fail "missing skills/dev-hub/assets/$a"
done
check "hub DECISIONS has the columns line" grep -qF '| ID | Date | Decision | Status | Supersedes | How to confirm |' skills/dev-hub/assets/DECISIONS.md
check "hub AGENTS has reading order" grep -qF 'Read in this order' skills/dev-hub/assets/AGENTS.md
# dev-research and dev-prd
for sk in dev-research dev-prd; do
  f=skills/$sk/SKILL.md
  if [ -f "$f" ]; then
    check "$sk is 120 lines or fewer" test "$(wc -l < "$f")" -le 120
    check "$sk contract path resolves" test -f "skills/$sk/../dev/references/dev-contract.md"
    check "$sk links the contract" grep -qF '../dev/references/dev-contract.md' "$f"
  else
    fail "missing $f"
  fi
done
for t in 'source beside every fact' unverified; do
  check "dev-research contains: $t" grep -qF -- "$t" skills/dev-research/SKILL.md
done
for t in 'NEEDS CLARIFICATION' 'at most 5' 'DECISIONS.md'; do
  check "dev-prd contains: $t" grep -qF -- "$t" skills/dev-prd/SKILL.md
done
prd=skills/dev-prd/assets/PRD.md
for t in '## Goals' '## Non-goals' '## Anti-goals' '## Behaviour contract' 'THE SYSTEM SHALL' 'B-001'; do
  check "PRD template contains: $t" grep -qF -- "$t" "$prd"
done
exit "$FAILED"
