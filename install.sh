#!/usr/bin/env bash
# Install (or remove) the eighteen RayStack skills for any agent that reads SKILL.md folders.
set -eu

# Resolve symlinks to this script so ROOT is the real checkout.
self=$0
while [ -L "$self" ]; do
  link=$(readlink "$self")
  case "$link" in /*) self=$link ;; *) self=$(dirname "$self")/$link ;; esac
done
ROOT=$(cd "$(dirname "$self")" && pwd -P)
SKILLS="raystack aws-billing-review aws-security-review aws-bottleneck-review infra-review scaling-review database-review app-security-review principle-ship principle-smallest-change principle-ask-with-question-tool principle-secrets-layout local-verify blog blog-topics blog-draft humanize blog-cover"

usage() {
  cat <<'USAGE'
Usage: install.sh [--agent claude|cursor|codex|grok|opencode|custom] [--dir <skills-dir>]
                  [--link] [--uninstall] [--dry-run] [--force] [-h|--help]

Copies the eighteen RayStack skills into the agent's skills directory (default agent: claude).
  --dir        skills directory; required with --agent custom, overrides the agent default
  --link       symlink to this checkout instead of copying
  --uninstall  remove exactly the eighteen RayStack skills from the target
  --dry-run    print what would happen, change nothing
  --force      also replace/remove same-named folders RayStack did not install
Same-named folders without the .raystack-installed marker (or a link into this checkout)
are skipped with a warning and the exit status is 1.
USAGE
}

die() { echo "install.sh: $*" >&2; exit 1; }

agent=claude dir="" dir_set=0 link=0 uninstall=0 dry=0 force=0 skipped=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) [ $# -ge 2 ] || die "--agent needs a value"; agent=$2; shift 2 ;;
    --dir) [ $# -ge 2 ] || die "--dir needs a value"; dir=$2; dir_set=1; shift 2 ;;
    --link) link=1; shift ;;
    --uninstall) uninstall=1; shift ;;
    --dry-run) dry=1; shift ;;
    --force) force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

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

if [ "$uninstall" = 1 ]; then
  for s in $SKILLS; do
    if [ -e "$dir/$s" ] || [ -L "$dir/$s" ]; then
      ! skip_foreign "$dir/$s" "$s" || continue
      echo "remove $dir/$s"
      run rm -rf "${dir:?}/${s:?}"
    fi
  done
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
    cat "$ROOT/VERSION" > "$tmp/.raystack-installed" || { rm -rf "$tmp"; die "marker failed for $s"; }
  fi
  rm -rf "$dest"
  mv "$tmp" "$dest"
done

[ -z "$hint" ] || echo "Tip: $agent also has a native plugin install: $hint"
echo "Note: the read-only guard hook is enforced automatically only in Claude Code."
echo "On other agents, pair reviews with read-only credentials. See docs/agents.md."
exit "$skipped"
