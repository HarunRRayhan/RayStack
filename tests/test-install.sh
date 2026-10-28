#!/usr/bin/env bash
# Tests for install.sh
# shellcheck disable=SC2015,SC2012  # pass/fail chains and ls counts are intentional
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=/dev/null
. ./tests/lib.sh
INSTALL=./install.sh
if [ ! -f "$INSTALL" ]; then fail "install.sh missing"; exit 1; fi
SKILLS="raystack aws-billing-review aws-security-review aws-bottleneck-review infra-review scaling-review database-review principle-ship principle-smallest-change principle-ask-with-question-tool principle-secrets-layout"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

count() { n=0; for s in $SKILLS; do [ -e "$1/$s/SKILL.md" ] && n=$((n + 1)); done; echo "$n"; }

# install twice into a dir that holds another skill
D="$T/a"; mkdir -p "$D/other-skill"; echo keep > "$D/other-skill/SKILL.md"
bash "$INSTALL" --dir "$D" >/dev/null; assert_eq "$?" 0 "install exits 0"
assert_eq "$(count "$D")" 11 "all eleven skills installed"
assert_eq "$(cat "$D/other-skill/SKILL.md")" keep "other-skill intact"
cp -R "$D" "$T/snap"
bash "$INSTALL" --dir "$D" >/dev/null
if diff -r "$T/snap" "$D" >/dev/null; then pass "second run identical"; else fail "second run changed tree"; fi
[ -x "$D/raystack/hooks/readonly-guard.sh" ] && pass "copied guard executable" || fail "guard not executable"
[ ! -e "$D/.denylist" ] && [ ! -e "$D/hooks" ] && [ ! -e "$D/scripts" ] && [ ! -e "$D/docs" ] && [ ! -e "$D/raystack/.denylist" ] \
  && pass "nothing outside skills/ copied" || fail "extra files copied"
assert_eq "$(ls "$D" | wc -l | tr -d ' ')" 12 "target holds eleven skills plus other-skill"

# uninstall removes only ours
bash "$INSTALL" --dir "$D" --uninstall >/dev/null
assert_eq "$(count "$D")" 0 "uninstall removed skills"
assert_eq "$(ls "$D")" other-skill "uninstall left other-skill"

# link
L="$T/l"
bash "$INSTALL" --dir "$L" --link >/dev/null 2>&1
links=0; for s in $SKILLS; do [ -L "$L/$s" ] && links=$((links + 1)); done
assert_eq "$links" 11 "--link makes eleven symlinks"
bash "$INSTALL" --dir "$L" >/dev/null
assert_eq "$([ -L "$L/raystack" ] && echo link || echo dir)" dir "copy replaces a symlink with a real dir"
bash "$INSTALL" --dir "$L" --uninstall >/dev/null
assert_eq "$(count "$L")" 0 "uninstall after link"

# dry run changes nothing
bash "$INSTALL" --dir "$T/dry" --dry-run >/dev/null
[ ! -e "$T/dry" ] && pass "--dry-run creates nothing" || fail "--dry-run created target"
bash "$INSTALL" --dir "$D" --uninstall --dry-run >/dev/null
bash "$INSTALL" --dir "$D" >/dev/null
bash "$INSTALL" --dir "$D" --uninstall --dry-run >/dev/null
assert_eq "$(count "$D")" 11 "--uninstall --dry-run removes nothing"

# refusals
bash "$INSTALL" --dir / >/dev/null 2>&1; assert_eq "$?" 1 "refuses /"
bash "$INSTALL" --dir "" >/dev/null 2>&1; assert_eq "$?" 1 "refuses empty dir"
bash "$INSTALL" --dir "$HOME" >/dev/null 2>&1; assert_eq "$?" 1 "refuses HOME"
bash "$INSTALL" --agent custom >/dev/null 2>&1; assert_eq "$?" 1 "custom needs --dir"
bash "$INSTALL" --agent nope >/dev/null 2>&1; assert_eq "$?" 1 "unknown agent"

# agent default dir, caveat, works from another cwd
H="$T/home"; mkdir -p "$H"
out=$(cd "$T" && HOME="$H" bash "$OLDPWD/$INSTALL" --agent codex 2>&1)
assert_eq "$(count "$H/.agents/skills")" 11 "codex default dir"
case "$out" in *docs/agents.md*) pass "prints guard caveat";; *) fail "no guard caveat";; esac
case "$out" in *"codex plugin"*) pass "prints plugin hint";; *) fail "no plugin hint";; esac

# foreign same-named dir is never deleted
F="$T/f"; mkdir -p "$F/infra-review"; F=$(cd "$F" && pwd -P); echo mine > "$F/infra-review/notes.txt"
err=$(bash "$INSTALL" --dir "$F" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" 1 "install exits 1 when a foreign dir is skipped"
assert_eq "$(cat "$F/infra-review/notes.txt")" mine "foreign dir preserved by install"
case "$err" in *"skipping $F/infra-review: not installed by RayStack (use --force to replace)"*) pass "skip warning";; *) fail "no skip warning: $err";; esac
assert_eq "$(count "$F")" 10 "other ten still installed"
bash "$INSTALL" --dir "$F" --uninstall >/dev/null 2>&1; assert_eq "$?" 1 "uninstall exits 1 on foreign dir"
assert_eq "$(cat "$F/infra-review/notes.txt")" mine "foreign dir preserved by uninstall"
assert_eq "$(find "$F" -mindepth 1 -maxdepth 1 | wc -l | tr -d " ")" 1 "uninstall removed only ours"
bash "$INSTALL" --dir "$F" --force >/dev/null 2>&1; assert_eq "$?" 0 "--force exits 0"
[ ! -e "$F/infra-review/notes.txt" ] && [ -f "$F/infra-review/SKILL.md" ] && pass "--force replaces foreign dir" || fail "--force did not replace"

# path with spaces
bash "$INSTALL" --dir "$T/with space/skills" >/dev/null; assert_eq "$(count "$T/with space/skills")" 11 "dir with spaces"

# source tree and HOME/. refused
bash "$INSTALL" --dir "$PWD/skills" >/dev/null 2>&1; assert_eq "$?" 1 "refuses source skills dir"
HOME="$H" bash "$INSTALL" --dir "$H/." >/dev/null 2>&1; assert_eq "$?" 1 "refuses HOME/."

# guard hook: copied review skills point at the installed guard and run it without CLAUDE_PLUGIN_ROOT
hook_cmd() { sed -n "s/^ *command: '\(.*\)'\$/\1/p" "$1"; }
G="$T/g dir"; bash "$INSTALL" --dir "$G" >/dev/null
for s in aws-billing-review database-review; do
  c=$(hook_cmd "$G/$s/SKILL.md")
  case "$c" in *CLAUDE_PLUGIN_ROOT*|'') fail "$s hook not rewritten: $c" ;; *) pass "$s hook rewritten" ;; esac
  printf '%s' '{"tool_input":{"command":"terraform destroy"}}' | env -u CLAUDE_PLUGIN_ROOT sh -c "$c" >/dev/null 2>&1
  assert_eq "$?" 2 "$s installed hook blocks a write"
  printf '%s' '{"tool_input":{"command":"git status"}}' | env -u CLAUDE_PLUGIN_ROOT sh -c "$c" >/dev/null 2>&1
  assert_eq "$?" 0 "$s installed hook allows a read"
done
# source frontmatter fails closed when the guard is not where it points
c=$(hook_cmd skills/aws-billing-review/SKILL.md)
err=$(printf '%s' '{"tool_input":{"command":"git status"}}' | env -u CLAUDE_PLUGIN_ROOT sh -c "$c" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" 2 "unresolved guard path blocks (fail closed)"
case "$err" in *"guard missing"*) pass "missing guard reason" ;; *) fail "missing guard reason (got '$err')" ;; esac
printf '%s' '{"tool_input":{"command":"terraform destroy"}}' | CLAUDE_PLUGIN_ROOT="$PWD" sh -c "$c" >/dev/null 2>&1
assert_eq "$?" 2 "plugin-root hook still runs the guard"
# --link cannot rewrite the hook: warn loudly
err=$(bash "$INSTALL" --dir "$T/lw" --link 2>&1 >/dev/null)
case "$err" in *WARNING*"block every Bash"*) pass "--link warns about the guard path" ;; *) fail "--link warning missing: $err" ;; esac
# a target path that cannot be embedded in the hook command is refused
bash "$INSTALL" --dir "$T/bad\"dir" >/dev/null 2>&1; assert_eq "$?" 1 "refuses quote in copy target"
[ ! -e "$T/bad\"dir" ] && pass "nothing created for bad target" || fail "bad target created"

# symlinked install.sh still finds the checkout
mkdir -p "$T/bin"; ln -s "$PWD/install.sh" "$T/bin/install.sh"
bash "$T/bin/install.sh" --dir "$T/viaLink" >/dev/null; assert_eq "$(count "$T/viaLink")" 11 "works via symlinked install.sh"

exit "$FAILED"
