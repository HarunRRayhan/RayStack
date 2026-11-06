#!/usr/bin/env bash
# Tests for install.sh
# shellcheck disable=SC2015,SC2012  # pass/fail chains and ls counts are intentional
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=/dev/null
. ./tests/lib.sh
INSTALL=./install.sh
if [ ! -f "$INSTALL" ]; then fail "install.sh missing"; exit 1; fi
SKILLS="raystack audit aws-billing-review aws-security-review aws-bottleneck-review infra-review scaling-review database-review app-security-review performance-review pipeline-security-review aws-readonly-setup principle-ship principle-smallest-change principle-ask-with-question-tool principle-secrets-layout local-verify dev dev-hub dev-research dev-prd dev-spec dev-plan dev-build dev-gaps dev-review dev-migrate dev-refactor architecture-review frontend-review reliability-review codebase-review cve-review rs"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export RAYSTACK_REGISTRY="$T/registry"

count() { n=0; for s in $SKILLS; do [ -e "$1/$s/SKILL.md" ] && n=$((n + 1)); done; echo "$n"; }

# install twice into a dir that holds another skill
D="$T/a"; mkdir -p "$D/other-skill"; echo keep > "$D/other-skill/SKILL.md"
bash "$INSTALL" --dir "$D" >/dev/null; assert_eq "$?" 0 "install exits 0"
assert_eq "$(count "$D")" 34 "all thirty-four skills installed"
assert_eq "$(cat "$D/other-skill/SKILL.md")" keep "other-skill intact"
assert_eq "$(find "$D" -maxdepth 1 -name ".raystack-tmp*" | wc -l | tr -d " ")" 0 "no staging folder left behind"
cp -R "$D" "$T/snap"
bash "$INSTALL" --dir "$D" >/dev/null
if diff -r "$T/snap" "$D" >/dev/null; then pass "second run identical"; else fail "second run changed tree"; fi
[ -x "$D/raystack/hooks/readonly-guard.sh" ] && pass "copied guard executable" || fail "guard not executable"
# The installed guard resolves gitleaks -c to the installed references/gitleaks.toml, from any cwd.
IC=$(cd "$D/raystack/references" && pwd -P)/gitleaks.toml
[ -f "$IC" ] && pass "gitleaks.toml installed" || fail "gitleaks.toml not installed"
gl() { jq -cn --arg c "gitleaks dir . --redact -f json -r - -c $1" '{tool_input:{command:$c}}' | (cd / && "$D/raystack/hooks/readonly-guard.sh" >/dev/null 2>&1); echo $?; }
assert_eq "$(gl "$IC")" 0 "installed guard allows its own gitleaks config"
assert_eq "$(gl "$(pwd -P)/skills/raystack/references/gitleaks.toml")" 2 "installed guard denies the checkout's config"
[ ! -e "$D/.denylist" ] && [ ! -e "$D/hooks" ] && [ ! -e "$D/scripts" ] && [ ! -e "$D/docs" ] && [ ! -e "$D/raystack/.denylist" ] \
  && pass "nothing outside skills/ copied" || fail "extra files copied"
assert_eq "$(ls "$D" | wc -l | tr -d ' ')" 35 "target holds thirty-four skills plus other-skill"

# uninstall removes only ours
bash "$INSTALL" --dir "$D" --uninstall >/dev/null
assert_eq "$(count "$D")" 0 "uninstall removed skills"
assert_eq "$(ls "$D")" other-skill "uninstall left other-skill"

# link
L="$T/l"
bash "$INSTALL" --dir "$L" --link >/dev/null 2>&1
links=0; for s in $SKILLS; do [ -L "$L/$s" ] && links=$((links + 1)); done
assert_eq "$links" 34 "--link makes thirty-four symlinks"
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
assert_eq "$(count "$D")" 34 "--uninstall --dry-run removes nothing"

# refusals
bash "$INSTALL" --dir / >/dev/null 2>&1; assert_eq "$?" 1 "refuses /"
bash "$INSTALL" --dir "" >/dev/null 2>&1; assert_eq "$?" 1 "refuses empty dir"
bash "$INSTALL" --dir "$HOME" >/dev/null 2>&1; assert_eq "$?" 1 "refuses HOME"
bash "$INSTALL" --agent custom >/dev/null 2>&1; assert_eq "$?" 1 "custom needs --dir"
bash "$INSTALL" --agent nope >/dev/null 2>&1; assert_eq "$?" 1 "unknown agent"

# agent default dir, caveat, works from another cwd
H="$T/home"; mkdir -p "$H"
out=$(cd "$T" && HOME="$H" bash "$OLDPWD/$INSTALL" --agent codex 2>&1)
assert_eq "$(count "$H/.agents/skills")" 34 "codex default dir"
case "$out" in *docs/agents.md*) pass "prints guard caveat";; *) fail "no guard caveat";; esac
case "$out" in *"type /raystack"*) pass "prints the next step";; *) fail "no next step";; esac
case "$out" in *"grok plugin marketplace"*) fail "stale grok tip";; *) pass "no stale grok tip";; esac
# A checkout under $HOME is recorded as ~/..., so a committed project install carries no home path.
mkdir -p "$H/rs" && cp -R install.sh skills VERSION "$H/rs/" && HOME="$H" bash "$H/rs/install.sh" --dir "$T/portable" >/dev/null 2>&1
assert_eq "$(sed -n 2p "$T/portable/raystack/.raystack-installed")" "source=~/rs" "marker uses ~ for home"
# --agent all installs for each agent found in $HOME; Grok only when it has no Claude or Cursor folder to read.
HA="$T/homeall"; mkdir -p "$HA/.claude" "$HA/.codex" "$HA/.grok"
outall=$(HOME="$HA" bash ./install.sh --agent all --yes 2>&1)
assert_eq "$(count "$HA/.claude/skills")" 34 "all: claude"
assert_eq "$(count "$HA/.agents/skills")" 34 "all: codex"
[ ! -d "$HA/.grok/skills" ] && pass "all: grok reads ~/.claude/skills" || fail "all: grok got its own copy"
case "$outall" in *"Installed for: Claude Code, Codex."*) pass "all: summary";; *) fail "all: summary (got $outall)";; esac
HN="$T/homenone"; mkdir -p "$HN"; HOME="$HN" bash ./install.sh --agent all --yes >/dev/null 2>&1
assert_eq "$(count "$HN/.claude/skills")" 34 "all: claude when no agent found"
# Agents that share a folder get one copy; each agent maps to its own global folder.
HS="$T/homeshared"; mkdir -p "$HS/.codex" "$HS/.cline" "$HS/.codeium/windsurf" "$HS/.gemini/antigravity"
outs=$(HOME="$HS" bash ./install.sh --agent all --yes 2>&1)
assert_eq "$(count "$HS/.codeium/windsurf/skills")" 34 "all: windsurf folder"
assert_eq "$(count "$HS/.gemini/antigravity/skills")" 34 "all: antigravity folder"
assert_eq "$(count "$HS/.gemini/skills")" 34 "all: gemini folder"
case "$outs" in *"same folder: Cline"*) pass "all: shared folder named";; *) fail "all: shared folder not named";; esac
HOME="$T/x" bash ./install.sh --agent nosuch >/dev/null 2>&1 && fail "unknown agent accepted" || pass "unknown agent rejected"
P="$T/projgem"; mkdir -p "$P"; HOME="$T/x" bash ./install.sh --agent gemini --project "$P" >/dev/null 2>&1
assert_eq "$(count "$P/.agents/skills")" 34 "gemini project folder"
HO="$T/homeclaw"; mkdir -p "$HO/.openclaw"; HOME="$HO" bash ./install.sh --agent all --yes >/dev/null 2>&1
assert_eq "$(count "$HO/.openclaw/skills")" 34 "all: openclaw folder"
bash -n get.sh && pass "get.sh parses" || fail "get.sh syntax"
[ "$(tail -1 get.sh | cut -c1-10)" = 'main "$@" ' ] && pass "get.sh runs main last" || fail "get.sh must end with main"
case "$out" in *"codex plugin"*) pass "prints plugin hint";; *) fail "no plugin hint";; esac

# foreign same-named dir is never deleted
F="$T/f"; mkdir -p "$F/infra-review"; F=$(cd "$F" && pwd -P); echo mine > "$F/infra-review/notes.txt"
err=$(bash "$INSTALL" --dir "$F" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" 1 "install exits 1 when a foreign dir is skipped"
assert_eq "$(cat "$F/infra-review/notes.txt")" mine "foreign dir preserved by install"
case "$err" in *"skipping $F/infra-review: not installed by RayStack (use --force to replace)"*) pass "skip warning";; *) fail "no skip warning: $err";; esac
assert_eq "$(count "$F")" 33 "other thirty-three still installed"
bash "$INSTALL" --dir "$F" --uninstall >/dev/null 2>&1; assert_eq "$?" 1 "uninstall exits 1 on foreign dir"
assert_eq "$(cat "$F/infra-review/notes.txt")" mine "foreign dir preserved by uninstall"
assert_eq "$(find "$F" -mindepth 1 -maxdepth 1 | wc -l | tr -d " ")" 1 "uninstall removed only ours"
bash "$INSTALL" --dir "$F" --force >/dev/null 2>&1; assert_eq "$?" 0 "--force exits 0"
[ ! -e "$F/infra-review/notes.txt" ] && [ -f "$F/infra-review/SKILL.md" ] && pass "--force replaces foreign dir" || fail "--force did not replace"

# retired skills: ours are removed on install and uninstall, foreign ones never
R="$T/r"; mkdir -p "$R/blog" "$R/humanize" "$R/blog-cover"; R=$(cd "$R" && pwd -P)
echo 0.5.0 > "$R/blog/.raystack-installed"; echo 0.5.0 > "$R/humanize/.raystack-installed"
echo mine > "$R/blog-cover/notes.txt"
out=$(bash "$INSTALL" --dir "$R" 2>&1)
[ ! -e "$R/blog" ] && [ ! -e "$R/humanize" ] && pass "install removes retired skills it installed" || fail "retired skills left"
assert_eq "$(cat "$R/blog-cover/notes.txt")" mine "foreign retired-name dir kept"
case "$out" in *"remove retired $R/blog"*) pass "reports retired removal";; *) fail "no retired removal line: $out";; esac
mkdir -p "$R/blog-draft"; echo 0.5.0 > "$R/blog-draft/.raystack-installed"
bash "$INSTALL" --dir "$R" --uninstall --dry-run >/dev/null 2>&1
[ -e "$R/blog-draft" ] && pass "--dry-run keeps retired skill" || fail "--dry-run removed retired skill"
bash "$INSTALL" --dir "$R" --uninstall >/dev/null 2>&1
[ ! -e "$R/blog-draft" ] && pass "uninstall removes retired skills it installed" || fail "uninstall left retired skill"
assert_eq "$(cat "$R/blog-cover/notes.txt")" mine "uninstall keeps foreign retired-name dir"

# a foreign rs skill is skipped with a note; raystack itself still installs
RS="$T/rs"; mkdir -p "$RS/rs"; RS=$(cd "$RS" && pwd -P); echo mine > "$RS/rs/notes.txt"
err=$(bash "$INSTALL" --dir "$RS" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" 1 "foreign rs: install exits 1"
assert_eq "$(cat "$RS/rs/notes.txt")" mine "foreign rs preserved"
case "$err" in *"/raystack still works"*) pass "foreign rs note";; *) fail "no rs note: $err";; esac
[ -f "$RS/raystack/SKILL.md" ] && pass "raystack installed beside foreign rs" || fail "raystack missing"
bash "$INSTALL" --dir "$RS" --force >/dev/null 2>&1
[ -f "$RS/rs/.raystack-installed" ] && pass "--force replaces foreign rs" || fail "--force kept foreign rs"

# path with spaces
bash "$INSTALL" --dir "$T/with space/skills" >/dev/null; assert_eq "$(count "$T/with space/skills")" 34 "dir with spaces"

# source tree and HOME/. refused
bash "$INSTALL" --dir "$PWD/skills" >/dev/null 2>&1; assert_eq "$?" 1 "refuses source skills dir"
HOME="$H" bash "$INSTALL" --dir "$H/." >/dev/null 2>&1; assert_eq "$?" 1 "refuses HOME/."

# guard hook: Claude Code sets CLAUDE_PLUGIN_ROOT to the plugin root (plugin) or to the skill's own
# folder (installed skill). Either way the hook finds the guard; with neither it fails closed.
hook_cmd() { sed -n "s/^ *command: '\(.*\)'\$/\1/p" "$1"; }
E="$T/empty-home"; mkdir -p "$E"
G="$T/g dir"; bash "$INSTALL" --dir "$G" >/dev/null
L2="$T/l2"; bash "$INSTALL" --dir "$L2" --link >/dev/null 2>&1
for s in aws-billing-review database-review; do
  c=$(hook_cmd skills/$s/SKILL.md)
  for root in "$G/$s" "$L2/$s" "$PWD/skills/$s" "$PWD"; do
    printf '%s' '{"tool_input":{"command":"terraform destroy"}}' | CLAUDE_PLUGIN_ROOT="$root" HOME="$E" sh -c "$c" >/dev/null 2>&1
    assert_eq "$?" 2 "$s hook blocks a write (root ${root#"$T"/})"
    printf '%s' '{"tool_input":{"command":"git status"}}' | CLAUDE_PLUGIN_ROOT="$root" HOME="$E" sh -c "$c" >/dev/null 2>&1
    assert_eq "$?" 0 "$s hook allows a read (root ${root#"$T"/})"
  done
done
c=$(hook_cmd skills/aws-billing-review/SKILL.md)
err=$(printf '%s' '{"tool_input":{"command":"git status"}}' | env -u CLAUDE_PLUGIN_ROOT HOME="$E" sh -c "$c" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" 2 "unresolved guard path blocks (fail closed)"
case "$err" in *"guard missing"*) pass "missing guard reason" ;; *) fail "missing guard reason (got '$err')" ;; esac
err=$(printf '%s' '{"tool_input":{"command":"git status"}}' | CLAUDE_PLUGIN_ROOT="$T/nowhere/x" HOME="$E" sh -c "$c" 2>&1 >/dev/null); rc=$?
assert_eq "$rc" 2 "wrong skill folder blocks (fail closed)"
# last fallback: ~/.claude/skills/raystack
GH="$T/global-home"; mkdir -p "$GH/.claude/skills"; cp -R skills/raystack "$GH/.claude/skills/raystack"
printf '%s' '{"tool_input":{"command":"terraform destroy"}}' | env -u CLAUDE_PLUGIN_ROOT HOME="$GH" sh -c "$c" >/dev/null 2>&1
assert_eq "$?" 2 "home fallback blocks a write"
printf '%s' '{"tool_input":{"command":"git status"}}' | env -u CLAUDE_PLUGIN_ROOT HOME="$GH" sh -c "$c" >/dev/null 2>&1
assert_eq "$?" 0 "home fallback allows a read"
# a target path that cannot be embedded in the hook command is refused
bash "$INSTALL" --dir "$T/bad\"dir" >/dev/null 2>&1; assert_eq "$?" 1 "refuses quote in copy target"
[ ! -e "$T/bad\"dir" ] && pass "nothing created for bad target" || fail "bad target created"

# symlinked install.sh still finds the checkout
mkdir -p "$T/bin"; ln -s "$PWD/install.sh" "$T/bin/install.sh"
bash "$T/bin/install.sh" --dir "$T/viaLink" >/dev/null; assert_eq "$(count "$T/viaLink")" 34 "works via symlinked install.sh"

# --project installs into the repo's agent folder (default: current folder)
P="$T/repo"; mkdir -p "$P"
bash "$INSTALL" --project "$P" >/dev/null; assert_eq "$(count "$P/.claude/skills")" 34 "--project installs to .claude/skills"
bash "$INSTALL" --agent codex --project "$P" >/dev/null; assert_eq "$(count "$P/.agents/skills")" 34 "--agent codex --project installs to .agents/skills"
P2="$T/repo2"; mkdir -p "$P2"; I=$PWD/install.sh
(cd "$P2" && bash "$I" --project >/dev/null); assert_eq "$(count "$P2/.claude/skills")" 34 "--project with no path uses the current folder"
bash "$INSTALL" --project "$T/missing" >/dev/null 2>&1; assert_eq "$?" 1 "--project refuses a missing folder"
grep -q "^$(cd "$P" && pwd -P)/.claude/skills	0$" "$RAYSTACK_REGISTRY" && pass "registry records the project target" || fail "registry missing project target"
bash "$INSTALL" --project "$P" --uninstall >/dev/null
grep -q "^$(cd "$P" && pwd -P)/.claude/skills	" "$RAYSTACK_REGISTRY" && fail "uninstall left the registry line" || pass "uninstall drops the registry line"

# --update pulls a newer version and reinstalls every recorded target
S="$T/src"; mkdir -p "$S"
git ls-files -z -co --exclude-standard | xargs -0 tar cf - | tar xf - -C "$S"
git -C "$S" init -q -b main && git -C "$S" add -A && git -C "$S" -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm v1
git clone -q "$S" "$T/co"
export RAYSTACK_REGISTRY="$T/registry-update"
bash "$T/co/install.sh" --dir "$T/u1" >/dev/null; bash "$T/co/install.sh" --project "$P" >/dev/null
echo 9.9.9 > "$S/VERSION"; git -C "$S" -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qam v2
bash "$T/co/install.sh" --update >/dev/null 2>&1; assert_eq "$?" 0 "--update exits 0"
assert_eq "$(head -1 "$T/u1/raystack/.raystack-installed")" 9.9.9 "--update refreshed the global target"
assert_eq "$(head -1 "$P/.claude/skills/raystack/.raystack-installed")" 9.9.9 "--update refreshed the project target"
bash "$T/co/install.sh" --update --dry-run >/dev/null 2>&1; assert_eq "$?" 1 "--update refuses --dry-run"
bash "$INSTALL" --project "$P" --link >/dev/null 2>&1; assert_eq "$?" 1 "--project refuses --link"
bash "$INSTALL" --project "$P" --dir "$T/x" >/dev/null 2>&1; assert_eq "$?" 1 "--project refuses --dir"
echo dirty >> "$T/co/README.md"; bash "$T/co/install.sh" --update >/dev/null 2>&1; assert_eq "$?" 1 "--update refuses a dirty checkout"
git -C "$T/co" checkout -q README.md
grep -q "^source=$T/co$\|^source=$(cd "$T/co" && pwd -P)$" "$T/u1/raystack/.raystack-installed" && pass "marker records the source checkout" || fail "marker lacks source"

exit "$FAILED"
