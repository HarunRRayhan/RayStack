#!/usr/bin/env bash
# Tests scripts/leak-check.sh in throwaway git repos.
cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/scripts/leak-check.sh"
# shellcheck source=/dev/null
. ./tests/lib.sh

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1
git init -q .
printf 'acmecorp\n# a comment\n\ndb.internal.example\n' > deny.txt
echo "hello world" > clean.txt
git add clean.txt

run() { "$@" >out.txt 2>err.txt; echo $?; }

assert_eq "$(run bash "$SCRIPT" deny.txt)" 0 "clean repo passes"

mkdir .mining; echo "AcmeCorp secret" > .mining/n.md   # untracked
assert_eq "$(run bash "$SCRIPT" deny.txt)" 0 "untracked .mining ignored"

echo "built for AcmeCorp" > leak.txt; git add leak.txt
assert_eq "$(run bash "$SCRIPT" deny.txt)" 1 "tracked hit (case-insensitive) fails"
if grep -q 'leak.txt:1' out.txt err.txt; then pass "prints file:line"; else fail "prints file:line"; fi
if grep -q 'term #1' out.txt err.txt; then pass "prints term index"; else fail "prints term index"; fi
if grep -qi 'acmecorp' out.txt err.txt 2>/dev/null; then fail "term leaked into output"; else pass "term not printed"; fi
git rm -q -f --cached leak.txt; rm leak.txt

# comment line must not be treated as a term: a tracked '#' would match if it were
echo "# not a term" > hash.txt; git add hash.txt
assert_eq "$(run bash "$SCRIPT" deny.txt)" 0 "comments and blank lines ignored"

echo "x db.internal.example y" > host.txt; git add host.txt
assert_eq "$(run env RAYSTACK_DENYLIST="$(printf '\nDB.INTERNAL.EXAMPLE\n')" bash "$SCRIPT")" 1 "env deny-list hit fails"
git rm -q -f --cached host.txt

assert_eq "$(run env -u RAYSTACK_DENYLIST bash "$SCRIPT")" 0 "no deny-list skips"
if grep -q 'leak-check skipped: no deny-list' err.txt; then pass "skip message on stderr"; else fail "skip message on stderr"; fi

assert_eq "$(run bash "$SCRIPT" missing.txt)" 2 "missing deny-list file exits 2"
if grep -q 'deny-list file not found: missing.txt' err.txt; then pass "missing file message"; else fail "missing file message"; fi

# whitespace-only and padded lines: blank is ignored, padded term is trimmed and still matches
printf '   \n\t\n' > ws.txt
assert_eq "$(run env -u RAYSTACK_DENYLIST bash "$SCRIPT" ws.txt)" 0 "whitespace-only deny-list skips"
echo "has padded-term here" > pad.txt; git add pad.txt
printf '  \n  padded-term  \n' > ws2.txt
assert_eq "$(run bash "$SCRIPT" ws2.txt)" 1 "padded term trimmed and matched"
git rm -q -f --cached pad.txt

# second term reports #2
echo "second-term here" > two.txt; git add two.txt
printf 'nomatch-one\nsecond-term\n' > two-deny.txt
assert_eq "$(run bash "$SCRIPT" two-deny.txt)" 1 "second term hits"
if grep -q 'term #2' out.txt err.txt; then pass "reports term #2"; else fail "reports term #2"; fi
git rm -q -f --cached two.txt

# outside a git repo: must fail closed, not report ok
N="$(mktemp -d)"
cp deny.txt "$N/deny.txt"
assert_eq "$(cd "$N" && run bash "$SCRIPT" deny.txt)" 2 "non-git dir exits 2"
if grep -q 'not a git repo' "$N/err.txt"; then pass "non-git message"; else fail "non-git message"; fi
rm -rf "$N"

exit "$FAILED"
