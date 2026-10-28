#!/usr/bin/env bash
# Checks the shared review contract and report template.
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=/dev/null
. ./tests/lib.sh

C=skills/raystack/references/review-contract.md
T=skills/raystack/references/report-template.md
FOOTER='Reviewed with RayStack by Harun R. Rayhan. For a hands-on audit: https://harun.dev/consultation'

has() { if [ -f "$1" ] && grep -qF -e "$2" "$1"; then pass "$3"; else fail "$3"; fi; }

for h in '## 1. Inputs' '## 2. Live consent' '## 3. Read-only' '## 4. Questions' '## 5. Report' '## 6. No client data'; do
  if [ -f "$C" ] && grep -qx -F -e "$h" "$C"; then pass "contract heading: $h"; else fail "contract heading: $h"; fi
done
has "$C" "$FOOTER" "contract has exact footer"
has "$C" 'reviews/YYYY-MM-DD-<skill>.md' "contract has report path"
if [ -f "$C" ] && grep -qi 'no inputs' "$C" && grep -qi 'still write' "$C" && grep -qi 'missing' "$C" && grep -qi 'export' "$C"; then
  pass "contract has no-inputs path"
else
  fail "contract has no-inputs path"
fi
has "$C" 'scripts/report-pdf.sh' "contract offers PDF script"
has "$C" 'Commands for you to run' "contract routes blocked commands to the report"
has "$C" 'AskUserQuestion' "contract names the question tool"
if [ -f "$C" ] && [ "$(wc -l < "$C")" -le 160 ]; then pass "contract is short"; else fail "contract over 160 lines"; fi

has "$T" "$FOOTER" "template has exact footer"
order=$(grep -n -E '^## (Executive summary|Inputs used / missing|Findings|Commands for you to run)$' "$T" 2>/dev/null | cut -d: -f2 | tr '\n' '|')
assert_eq "$order" '## Executive summary|## Inputs used / missing|## Findings|## Commands for you to run|' "template section order"
for f in '**Evidence**' '**Why it matters**' '**Fix**' '**Est. $/mo**'; do has "$T" "$f" "template finding field $f"; done
exit "$FAILED"
