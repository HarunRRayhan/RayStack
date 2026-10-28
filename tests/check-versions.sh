#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

# One line per manifest: "file|jq filter". plugin.json is the Codex (portable Agent Plugins) manifest.
# Grok reads the .claude-plugin/ files, so it has no manifest of its own.
MANIFESTS=(
  ".claude-plugin/plugin.json|.version"
  ".claude-plugin/marketplace.json|.plugins[].version"
  ".cursor-plugin/plugin.json|.version"
  "plugin.json|.version"
)

VERSION=$(tr -d '[:space:]' < VERSION)
for m in "${MANIFESTS[@]}"; do
  file=${m%%|*}
  filter=${m#*|}
  if [ ! -f "$file" ]; then fail "missing manifest: $file"; continue; fi
  while IFS= read -r v; do
    assert_eq "$v" "$VERSION" "$file version"
  done < <(jq -r "$filter" "$file")
done
exit "$FAILED"
