#!/usr/bin/env bash
# Install (or remove) the thirty RayStack skills for any agent that reads SKILL.md folders.
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
SKILLS="raystack aws-billing-review aws-security-review aws-bottleneck-review infra-review scaling-review database-review app-security-review performance-review pipeline-security-review aws-readonly-setup principle-ship principle-smallest-change principle-ask-with-question-tool principle-secrets-layout local-verify dev dev-hub dev-research dev-prd dev-spec dev-plan dev-build dev-gaps dev-review dev-migrate architecture-review frontend-review reliability-review codebase-review"

usage() {
  cat <<'USAGE'
Usage: install.sh [--agent claude|cursor|codex|grok|opencode|custom] [--dir <skills-dir>]
                  [--project [<repo>]] [--link] [--uninstall] [--update] [--dry-run]
                  [--force] [-h|--help]

Copies the thirty RayStack skills into the agent's skills directory (default agent: claude).
  --dir        skills directory; required with --agent custom, overrides the agent default
  --project    install into a repo (default: the current folder) for that agent, e.g.
               <repo>/.claude/skills, so everyone who clones the repo gets RayStack
  --update     pull the latest RayStack into this checkout, then reinstall every place
               this checkout installed to (global and project); other flags are ignored
  --link       symlink to this checkout instead of copying
  --uninstall  remove exactly the thirty RayStack skills from the target
  --dry-run    print what would happen, change nothing
  --force      also replace/remove same-named folders RayStack did not install
Same-named folders without the .raystack-installed marker (or a link into this checkout)
are skipped with a warning and the exit status is 1.
USAGE
}

die() { echo "install.sh: $*" >&2; exit 1; }

agent=claude dir="" dir_set=0 link=0 uninstall=0 dry=0 force=0 skipped=0 project="" update=0
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
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

if [ "$update" = 1 ]; then
  [ -d "$ROOT/.git" ] || die "--update needs a git checkout (clone it, see the README)"
  [ "$dry" = 0 ] || die "--update does not support --dry-run"
  [ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ] || die "$ROOT has local changes; commit or discard them first"
  git -C "$ROOT" pull --ff-only --quiet || die "git pull failed in $ROOT"
  echo "RayStack $(cat "$ROOT/VERSION")"
  rc=0 n=0
  if [ -f "$REGISTRY" ]; then
    while IFS="$(printf '\t')" read -r d l; do
      [ -n "$d" ] && [ -d "$d" ] || continue
      # only targets this checkout installed: a link into it, or a copy whose marker names it
      if [ -L "$d/raystack" ]; then [ "$(readlink "$d/raystack")" = "$ROOT/skills/raystack" ] || continue
      else grep -qxF "source=$ROOT" "$d/raystack/.raystack-installed" 2>/dev/null || continue; fi
      n=$((n + 1))
      if [ "$l" = 1 ]; then "$ROOT/install.sh" --dir "$d" --link || rc=1
      else "$ROOT/install.sh" --dir "$d" || rc=1; fi
    done < "$REGISTRY"
  fi
  [ "$n" -gt 0 ] || "$ROOT/install.sh" || rc=1  # nothing recorded yet: the default global install
  exit "$rc"
fi

hint=""
case "$agent" in
  claude)   default="$HOME/.claude/skills";   hint="claude plugin marketplace add HarunRRayhan/RayStack && claude plugin install raystack@raystack" ;;
  cursor)   default="$HOME/.cursor/skills";   hint="cursor-agent plugin marketplace add <gitUrl> (see docs/agents.md)" ;;
  codex)    default="$HOME/.agents/skills";   hint="codex plugin marketplace add HarunRRayhan/RayStack && codex plugin add raystack@raystack" ;;
  grok)     default="$HOME/.grok/skills";     hint="grok plugin marketplace add HarunRRayhan/RayStack && grok plugin install raystack --trust" ;;
  opencode) default="$HOME/.config/opencode/skills" ;; # shortcut: not in docs/agents.md, unverified; pass --dir if yours differs
  custom)   default="" ;;
  *) die "unknown agent: $agent" ;;
esac
if [ -n "$project" ]; then
  [ "$dir_set" = 0 ] || die "use --project or --dir, not both"
  [ "$link" = 0 ] || die "--project copies the skills so they can be committed; --link is not allowed"
  project=$(cd "$project" && pwd -P)
  case "$agent" in
    claude)   dir="$project/.claude/skills" ;;
    cursor)   dir="$project/.cursor/skills" ;;
    codex)    dir="$project/.agents/skills" ;;
    grok)     dir="$project/.claude/skills" ;;  # Grok reads .claude/skills (see docs/agents.md)
    opencode) dir="$project/.opencode/skills" ;; # shortcut: unverified, pass --dir if yours differs
    custom)   die "--project needs a named --agent; use --dir for a custom path" ;;
  esac
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
for s in $SKILLS; do
  dest="$dir/$s"
  ! skip_foreign "$dest" "$s" || continue
  if [ "$link" = 1 ]; then
    echo "link $dest -> $ROOT/skills/$s"
    if [ "$dry" = 1 ]; then echo "[dry-run] ln -s"; continue; fi
    tmp="$dir/.raystack-tmp.$$.$s"
    rm -rf "$tmp"
    ln -s "$ROOT/skills/$s" "$tmp"
  else
    echo "copy $ROOT/skills/$s -> $dest"
    if [ "$dry" = 1 ]; then echo "[dry-run] cp -R"; continue; fi
    tmp="$dir/.raystack-tmp.$$.$s"
    rm -rf "$tmp"
    cp -R "$ROOT/skills/$s" "$tmp" || { rm -rf "$tmp"; die "copy failed for $s"; }
    { cat "$ROOT/VERSION"; echo "source=$ROOT"; } > "$tmp/.raystack-installed" || { rm -rf "$tmp"; die "marker failed for $s"; }
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
echo "RayStack $(cat "$ROOT/VERSION") installed in $dir. Update later with: $ROOT/install.sh --update"
[ -z "$hint" ] || echo "Tip: $agent also has a native plugin install: $hint"
echo "Note: the read-only guard hook is enforced automatically only in Claude Code."
echo "On other agents, pair reviews with read-only credentials. See docs/agents.md."
exit "$skipped"
