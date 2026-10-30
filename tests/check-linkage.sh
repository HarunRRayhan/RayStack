#!/usr/bin/env bash
# Each review skill links the shared contract, its checklist and the guard hook.
# The entry skill names all seven reviews. The router hands development to dev.
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
  check "raystack names dev" grep -qF '`dev`' "$entry"
else
  fail "missing $entry"
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
check "principle-ship checks docs still match" grep -qF 'docs still match' skills/principle-ship/SKILL.md

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
    todo in-progress 'done' done-with-concerns needs-context blocked WHEN 'THE SYSTEM SHALL' B-001 'inline review' 'at most 5' 'Shipped:' 'Committed:'; do
    check "dev-contract contains: $t" grep -qF -- "$t" "$dc"
  done
  check "dev-contract links the reviewer checklist" grep -qF '../../dev-build/references/reviewer.md' "$dc"
  check "dev-contract reviewer path resolves" test -f skills/dev/references/../../dev-build/references/reviewer.md
else
  fail "missing $dc"
fi
dp=skills/dev/references/principles.md
if [ -f "$dp" ]; then
  check "principles has 11 numbered items" test "$(grep -cE '^[0-9]+\. ' "$dp")" -eq 11
  check "principles has a reviewer rubric" grep -qxF '## Reviewer rubric' "$dp"
  check "principles points to principle-smallest-change" grep -qF 'principle-smallest-change' "$dp"
  check "principles replaces SOLID" grep -qF 'replaces SOLID' "$dp"
else
  fail "missing $dp"
fi
dv=skills/dev/SKILL.md
if [ -f "$dv" ]; then
  for t in Quick Standard Full replan 'no PRD' ledger 'references/dev-contract.md' 'Shipped:' pointer 'hub path' '../dev-hub/assets/DECISIONS.md' Analyze 'Always review it, even for one line'; do
    check "dev contains: $t" grep -qF -- "$t" "$dv"
  done
  check "dev DECISIONS asset resolves" test -f skills/dev/../dev-hub/assets/DECISIONS.md
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
check "hub AGENTS has no one-at-a-time rule" bash -c '! grep -qF "one at a time" skills/dev-hub/assets/AGENTS.md'
check "PRD template is project-neutral" bash -c '! grep -qF skills/dev/ skills/dev-prd/assets/PRD.md'
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
# dev-spec and dev-plan
for sk in dev-spec dev-plan; do
  f=skills/$sk/SKILL.md
  if [ -f "$f" ]; then
    check "$sk is 120 lines or fewer" test "$(wc -l < "$f")" -le 120
    check "$sk contract path resolves" test -f "skills/$sk/../dev/references/dev-contract.md"
    check "$sk links the contract" grep -qF '../dev/references/dev-contract.md' "$f"
  else
    fail "missing $f"
  fi
done
for t in 'Serves:' '## Complexity' 'docs/principles.md' '## Behaviours'; do
  check "dev-spec contains: $t" grep -qF -- "$t" skills/dev-spec/SKILL.md
done
for t in analyze 'NEEDS CLARIFICATION' 'Every task covers' 'vertical slice'; do
  check "dev-plan contains: $t" grep -qF -- "$t" skills/dev-plan/SKILL.md
done
for t in 'Covers:' 'Tests:' '## Analyze'; do
  check "plan template contains: $t" grep -qF -- "$t" skills/dev-plan/assets/plan.md
done
# dev-build: skill, its two prompt templates and the contract link
bv=skills/dev-build/SKILL.md
if [ -f "$bv" ]; then
  for t in ledger converge 'inline review' 'cost if wrong' 'final review' principle-ship 'docs still match' 'fix rounds' done-with-concerns 'Shipped:' 'Committed:' 'inline whole-branch'; do
    check "dev-build contains: $t" grep -qF -- "$t" "$bv"
  done
  check "dev-build writes Shipped only after merge" grep -qF 'confirms the merge' "$bv"
  check "dev-build is 120 lines or fewer" test "$(wc -l < "$bv")" -le 120
  check "dev-build contract path resolves" test -f "skills/dev-build/../dev/references/dev-contract.md"
  check "dev-build links the contract" grep -qF '../dev/references/dev-contract.md' "$bv"
  for r in implementer reviewer; do
    check "dev-build links references/$r.md" grep -qF "references/$r.md" "$bv"
    check "dev-build references/$r.md exists" test -f "skills/dev-build/references/$r.md"
  done
else
  fail "missing $bv"
fi
for t in weakened B-; do
  check "dev-build reviewer contains: $t" grep -qF -- "$t" skills/dev-build/references/reviewer.md
done
check "dev-build implementer contains: needs-context" grep -qF needs-context skills/dev-build/references/implementer.md
exit "$FAILED"
