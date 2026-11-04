#!/usr/bin/env bash
# Install (or remove) the thirty-two RayStack skills for any agent that reads SKILL.md folders.
set -eu

# Resolve symlinks to this script so ROOT is the real checkout.
self=$0
while [ -L "$self" ]; do
  link=$(readlink "$self")
  case "$link" in /*) self=$link ;; *) self=$(dirname "$self")/$link ;; esac
done
ROOT=$(cd "$(dirname "$self")" && pwd -P)
# Skills earlier versions shipped; removed from the target only when RayStack installed them.
RETIRED="blog blog-topics blog-draft humanize blog-cover"
SKILLS="raystack audit aws-billing-review aws-security-review aws-bottleneck-review infra-review scaling-review database-review app-security-review performance-review pipeline-security-review aws-readonly-setup principle-ship principle-smallest-change principle-ask-with-question-tool principle-secrets-layout local-verify dev dev-hub dev-research dev-prd dev-spec dev-plan dev-build dev-gaps dev-review dev-migrate architecture-review frontend-review reliability-review codebase-review cve-review"

usage() {
  cat <<'USAGE'
Usage: install.sh [--agent all|<agent>|custom] [--dir <skills-dir>] [--project [<repo>]]
                  [--link] [--uninstall] [--update] [--dry-run] [--yes] [--force] [-h|--help]

Copies the thirty-two RayStack skills into an agent's skills directory (default agent: claude).
Agents: claude codex cursor grok antigravity gemini copilot windsurf cline kiro roo kilo amp
goose opencode qwen trae junie augment warp zed openhands continue openclaw
clawdbot moltbot.
  --agent all  every agent found in your home folder; asks per agent at a terminal
  --yes        with --agent all, install for every agent found without asking
  --dir        skills directory; required with --agent custom, overrides the agent default
  --project    install into a repo (default: the current folder) for that agent, e.g.
               <repo>/.claude/skills, so everyone who clones the repo gets RayStack
  --update     pull the latest RayStack into this checkout, then reinstall every place
               this checkout installed to (global and project); other flags are ignored
  --link       symlink to this checkout instead of copying
  --uninstall  remove exactly the thirty-two RayStack skills from the target
  --dry-run    print what would happen, change nothing
  --force      also replace/remove same-named folders RayStack did not install
Same-named folders without the .raystack-installed marker (or a link into this checkout)
are skipped with a warning and the exit status is 1.
USAGE
}

die() { echo "install.sh: $*" >&2; exit 1; }

all_args=("$@")
agent=claude dir="" dir_set=0 link=0 uninstall=0 dry=0 force=0 skipped=0 project="" update=0 yes=0
# Every target installed from this checkout, one per line: <dir><TAB><link 0|1>. --update reads it.
REGISTRY=${RAYSTACK_REGISTRY:-$HOME/.raystack-installs}
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) [ $# -ge 2 ] || die "--agent needs a value"; agent=$2; shift 2 ;;
    --dir) [ $# -ge 2 ] || die "--dir needs a value"; dir=$2; dir_set=1; shift 2 ;;
    --project)
      if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then project=$2; shift 2; else project=$PWD; shift; fi
      [ -d "$project" ] || die "--project: no such folder: $project" ;;
    --update) update=1; shift ;;
    --link) link=1; shift ;;
    --uninstall) uninstall=1; shift ;;
    --dry-run) dry=1; shift ;;
    --force) force=1; shift ;;
    --yes|-y) yes=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

# The marker names the checkout with ~ for $HOME, so a committed project install carries no home path.
src="source=$ROOT"; hp=$(cd "$HOME" 2>/dev/null && pwd -P) || hp=$HOME
case "$ROOT" in "$hp"/*) src="source=~${ROOT#"$hp"}" ;; "$HOME"/*) src="source=~${ROOT#"$HOME"}" ;; esac

if [ "$update" = 1 ]; then
  [ -d "$ROOT/.git" ] || die "--update needs a git checkout (clone it, see the README)"
  [ "$dry" = 0 ] || die "--update does not support --dry-run"
  [ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ] || die "$ROOT has local changes; commit or discard them first"
  git -C "$ROOT" pull --ff-only --quiet || die "git pull failed in $ROOT"
  echo "RayStack $(cat "$ROOT/VERSION")"
  rc=0 n=0
  if [ -f "$REGISTRY" ]; then
    while IFS="$(printf '\t')" read -r d l; do
      if [ -z "$d" ] || [ ! -d "$d" ]; then continue; fi
      # only targets this checkout installed: a link into it, or a copy whose marker names it
      if [ -L "$d/raystack" ]; then [ "$(readlink "$d/raystack")" = "$ROOT/skills/raystack" ] || continue
      else grep -qxF -e "$src" -e "source=$ROOT" "$d/raystack/.raystack-installed" 2>/dev/null || continue; fi
      n=$((n + 1))
      if [ "$l" = 1 ]; then RAYSTACK_QUIET=1 "$ROOT/install.sh" --dir "$d" --link || rc=1
      else RAYSTACK_QUIET=1 "$ROOT/install.sh" --dir "$d" || rc=1; fi
    done < "$REGISTRY"
  fi
  [ "$n" -gt 0 ] || RAYSTACK_QUIET=1 "$ROOT/install.sh" || rc=1  # nothing recorded yet: the default global install
  echo "Start a new agent session to load the update."
  exit "$rc"
fi

# One row per agent: name|display name|folder that shows it is installed|global skills folder|
# project skills folder. Paths are relative to $HOME and to the repo. Claude Code, Codex,
# Cursor and Grok are tested (docs/agents.md); the rest come from the skills CLI's agent table.
AGENTS='claude|Claude Code|.claude|.claude/skills|.claude/skills
codex|Codex|.codex|.agents/skills|.agents/skills
cursor|Cursor|.cursor|.cursor/skills|.cursor/skills
grok|Grok Build|.grok|.grok/skills|.claude/skills
antigravity|Antigravity|.gemini/antigravity|.gemini/antigravity/skills|.agents/skills
gemini|Gemini CLI|.gemini|.gemini/skills|.agents/skills
copilot|GitHub Copilot|.copilot|.copilot/skills|.agents/skills
windsurf|Windsurf|.codeium/windsurf|.codeium/windsurf/skills|.windsurf/skills
cline|Cline|.cline|.agents/skills|.agents/skills
kiro|Kiro|.kiro|.kiro/skills|.kiro/skills
roo|Roo Code|.roo|.roo/skills|.roo/skills
kilo|Kilo Code|.kilo|.kilo/skills|.agents/skills
amp|Amp|.config/amp|.config/agents/skills|.agents/skills
goose|Goose|.config/goose|.config/goose/skills|.goose/skills
opencode|OpenCode|.config/opencode|.config/opencode/skills|.opencode/skills
qwen|Qwen Code|.qwen|.qwen/skills|.qwen/skills
trae|Trae|.trae|.trae/skills|.trae/skills
junie|Junie|.junie|.junie/skills|.junie/skills
augment|Augment|.augment|.augment/skills|.augment/skills
warp|Warp|.warp|.agents/skills|.agents/skills
zed|Zed|.config/zed|.agents/skills|.agents/skills
openhands|OpenHands|.openhands|.openhands/skills|.openhands/skills
continue|Continue|.continue|.continue/skills|.continue/skills
openclaw|OpenClaw (Clawdbot)|.openclaw|.openclaw/skills|skills
clawdbot|Clawdbot|.clawdbot|.clawdbot/skills|skills
moltbot|Moltbot|.moltbot|.moltbot/skills|skills'
# agent_field <name> <column 2-5>
agent_field() { printf '%s\n' "$AGENTS" | awk -F'|' -v n="$1" -v c="$2" '$1 == n { print $c }'; }

hint=""
if [ "$agent" = all ]; then
  [ "$dir_set" = 0 ] || die "--agent all uses each agent's own folder; drop --dir"
  col=4; [ -z "$project" ] || col=5
  # Agents found in $HOME, one per target folder (several agents share ~/.agents/skills).
  found="" seen="" labels="" shared=""
  while IFS='|' read -r n label mark g p; do
    [ -d "$HOME/$mark" ] || continue
    # Grok reads ~/.claude/skills and ~/.cursor/skills, so it needs its own copy only without them.
    if [ "$n" = grok ] && [ -z "$project" ] && { [ -d "$HOME/.claude" ] || [ -d "$HOME/.cursor" ]; }; then continue; fi
    t=$g; [ "$col" = 4 ] || t=$p
    case " $seen " in *" $t "*) shared="$shared, $label"; continue ;; esac
    seen="$seen $t" found="$found $n" labels="$labels, $label"
  done <<EOF
$AGENTS
EOF
  [ -n "$found" ] || { found=" claude" labels=", Claude Code"; }
  # Ask per agent when a person is at a terminal; agents and CI get every one found.
  if [ "$yes" = 0 ] && [ "$uninstall" = 0 ] && [ "$dry" = 0 ] && { : </dev/tty; } 2>/dev/null; then
    echo "Found: ${labels#, }."
    picked=""
    for n in $found; do
      t=$(agent_field "$n" "$col")
      # shellcheck disable=SC2088  # a literal ~ for display
      [ -n "$project" ] && where="$project/$t" || where='~/'"$t"
      printf 'Install RayStack for %s (%s)? [Y/n] ' "$(agent_field "$n" 2)" "$where" > /dev/tty
      read -r reply < /dev/tty || reply=n
      case "$reply" in [Nn]*) ;; *) picked="$picked $n" ;; esac
    done
    found=$picked
    [ -n "$found" ] || { echo "Nothing installed."; exit 0; }
  fi
  rest=() i=0
  while [ "$i" -lt "${#all_args[@]}" ]; do
    if [ "${all_args[$i]}" = --agent ]; then i=$((i + 2)); else rest+=("${all_args[$i]}"); i=$((i + 1)); fi
  done
  rc=0 names=""
  for a in $found; do
    RAYSTACK_QUIET=1 "$ROOT/install.sh" ${rest[@]+"${rest[@]}"} --agent "$a" || rc=1
    names="$names, $(agent_field "$a" 2)"
  done
  [ "$dry" = 1 ] || [ "$uninstall" = 1 ] || [ "$rc" != 0 ] || {
    command -v jq >/dev/null 2>&1 || echo "Warning: jq is not installed. In Claude Code the review guard blocks every shell command without it. Install jq (brew install jq, apt install jq)."
    [ -z "$shared" ] || echo "Also covered, as they read the same folder: ${shared#, }."
    echo "Installed for: ${names#, }. Next: start a new agent session and type /raystack. Update later with: $ROOT/install.sh --update"
  }
  exit "$rc"
fi
case "$agent" in
  claude) hint="claude plugin marketplace add HarunRRayhan/RayStack && claude plugin install raystack@raystack" ;;
  cursor) hint="cursor-agent plugin marketplace add <gitUrl> (see docs/agents.md)" ;;
  codex)  hint="codex plugin marketplace add HarunRRayhan/RayStack && codex plugin add raystack@raystack" ;;
  grok)   hint="grok plugin install HarunRRayhan/RayStack --trust" ;;
esac
if [ "$agent" = custom ]; then default=""
else
  g=$(agent_field "$agent" 4)
  [ -n "$g" ] || die "unknown agent: $agent (known: all custom $(printf '%s\n' "$AGENTS" | cut -d'|' -f1 | tr '\n' ' '))"
  default="$HOME/$g"
fi
if [ -n "$project" ]; then
  [ "$dir_set" = 0 ] || die "use --project or --dir, not both"
  [ "$link" = 0 ] || die "--project copies the skills so they can be committed; --link is not allowed"
  [ "$agent" != custom ] || die "--project needs a named --agent; use --dir for a custom path"
  project=$(cd "$project" && pwd -P)
  dir="$project/$(agent_field "$agent" 5)"
  dir_set=1 hint=""
fi
if [ "$dir_set" = 0 ]; then
  [ "$agent" != custom ] || die "--agent custom requires --dir"
  dir=$default
fi

# Canonicalise when the target exists (closes "$HOME/." and symlink tricks), then refuse
# empty, /, $HOME itself and the source tree.
if [ -n "$dir" ] && [ -d "$dir" ]; then dir=$(cd "$dir" && pwd -P); fi
while [ "${#dir}" -gt 1 ] && [ "${dir%/}" != "$dir" ]; do dir=${dir%/}; done
home=${HOME:-}
if [ -n "$home" ] && [ -d "$home" ]; then home=$(cd "$home" && pwd -P); fi
while [ "${#home}" -gt 1 ] && [ "${home%/}" != "$home" ]; do home=${home%/}; done
if [ -z "$dir" ] || [ "$dir" = "/" ] || [ "$dir" = "$home" ] || [ "$dir" = "$ROOT/skills" ]; then
  die "refusing unsafe target: '$dir'"
fi

# ours <dest> <name>: a link into this checkout, or a real dir carrying our marker.
ours() {
  if [ -L "$1" ]; then [ "$(readlink "$1")" = "$ROOT/skills/$2" ]; else [ -f "$1/.raystack-installed" ]; fi
}
# skip_foreign <dest>: true (and warns) when dest exists, is not ours and --force is off.
skip_foreign() {
  { [ -e "$1" ] || [ -L "$1" ]; } || return 1
  ours "$1" "$2" && return 1
  [ "$force" = 0 ] || return 1
  echo "skipping $1: not installed by RayStack (use --force to replace)" >&2
  skipped=1
}

run() { if [ "$dry" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }
# remove_retired: delete retired skills this tool installed; never touch foreign ones.
remove_retired() {
  for s in $RETIRED; do
    if { [ -e "$dir/$s" ] || [ -L "$dir/$s" ]; } && ours "$dir/$s" "$s"; then
      echo "remove retired $dir/$s"
      run rm -rf "${dir:?}/${s:?}"
    fi
  done
}

if [ "$uninstall" = 1 ]; then
  remove_retired
  for s in $SKILLS; do
    if [ -e "$dir/$s" ] || [ -L "$dir/$s" ]; then
      ! skip_foreign "$dir/$s" "$s" || continue
      echo "remove $dir/$s"
      run rm -rf "${dir:?}/${s:?}"
    fi
  done
  if [ "$dry" = 0 ] && [ -f "$REGISTRY" ]; then
    rtmp=$(mktemp "$REGISTRY.XXXXXX") && awk -F'\t' -v d="$dir" '$1 != d' "$REGISTRY" > "$rtmp" && mv "$rtmp" "$REGISTRY"
  fi
  [ "$dry" = 1 ] || echo "RayStack removed from $dir. The checkout stays in $ROOT; delete it too if you are done."
  exit "$skipped"
fi

for s in $SKILLS; do [ -f "$ROOT/skills/$s/SKILL.md" ] || die "missing source skill: $s"; done
# Copies embed "$dir" in each review's hook command (a quoted shell string inside YAML).
if [ "$link" = 0 ]; then
  case "$dir" in *[\"\'\$\`\\\&]*|*"
"*) die "target path holds a quote, \$, backtick, backslash, & or newline: '$dir'" ;; esac
fi
run mkdir -p "$dir"
[ "$dry" = 1 ] || dir=$(cd "$dir" && pwd -P)
# Stage one level down: agents scan $dir/*/SKILL.md, so a staged copy is never listed as a skill.
stage="$dir/.raystack-tmp.$$"
[ "$dry" = 1 ] || { rm -rf "$stage"; mkdir "$stage"; trap 'rm -rf "$stage"' EXIT; }
for s in $SKILLS; do
  dest="$dir/$s"
  ! skip_foreign "$dest" "$s" || continue
  if [ "$link" = 1 ]; then
    echo "link $dest -> $ROOT/skills/$s"
    if [ "$dry" = 1 ]; then echo "[dry-run] ln -s"; continue; fi
    tmp="$stage/$s"
    rm -rf "$tmp"
    ln -s "$ROOT/skills/$s" "$tmp"
  else
    echo "copy $ROOT/skills/$s -> $dest"
    if [ "$dry" = 1 ]; then echo "[dry-run] cp -R"; continue; fi
    tmp="$stage/$s"
    rm -rf "$tmp"
    cp -R "$ROOT/skills/$s" "$tmp" || { rm -rf "$tmp"; die "copy failed for $s"; }
    { cat "$ROOT/VERSION"; echo "$src"; } > "$tmp/.raystack-installed" || { rm -rf "$tmp"; die "marker failed for $s"; }
  fi
  rm -rf "$dest"
  mv "$tmp" "$dest"
done

remove_retired
if [ "$dry" = 0 ]; then
  line="$dir$(printf '\t')$link"
  if touch "$REGISTRY" 2>/dev/null && ! grep -qxF "$line" "$REGISTRY"; then
    rtmp=$(mktemp "$REGISTRY.XXXXXX") && { awk -F'\t' -v d="$dir" '$1 != d' "$REGISTRY"; echo "$line"; } > "$rtmp" && mv "$rtmp" "$REGISTRY"
  fi
fi
echo "RayStack $(cat "$ROOT/VERSION") installed in $dir."
[ -n "${RAYSTACK_QUIET:-}" ] && exit "$skipped"
command -v jq >/dev/null 2>&1 || echo "Warning: jq is not installed. In Claude Code the review guard blocks every shell command without it. Install jq (brew install jq, apt install jq)."
echo "Next: start a new agent session and type /raystack. Update later with: $ROOT/install.sh --update"
[ -z "$hint" ] || echo "Tip: $agent also has a native plugin install: $hint"
[ "$agent" = claude ] || echo "Note: the read-only guard runs only in Claude Code. On $agent, give reviews read-only credentials (docs/agents.md)."
exit "$skipped"
