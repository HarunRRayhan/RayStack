#!/usr/bin/env bash
# Build the ZIP for OpenAI's plugin directory (platform.openai.com/plugins).
# Usage: build-codex-zip.sh [out-dir]   (default: dist/). Prints the ZIP path.
# The Codex manifest lives only in the ZIP: the repo's own manifests stay as they are.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/raystack/.codex-plugin" "$OUT"
cp -R "$ROOT/skills" "$ROOT/assets" "$ROOT/README.md" "$ROOT/LICENSE" "$STAGE/raystack/"

jq --arg v "$VERSION" '{
  name, version: $v, description, author, homepage, repository, license, keywords,
  skills: "./skills/",
  interface: {
    displayName: "RayStack",
    shortDescription: "Plan, build and review code",
    longDescription: .description,
    developerName: .author.name,
    category: "Productivity",
    capabilities: [],
    websiteURL: .homepage,
    supportURL: "https://github.com/HarunRRayhan/RayStack/issues",
    defaultPrompt: ["/raystack new project", "/raystack project review", "/raystack scan all"],
    composerIcon: "./assets/logo.png",
    logo: "./assets/logo.png"
  }
}' "$ROOT/plugin.json" > "$STAGE/raystack/.codex-plugin/plugin.json"

# Self-check: the limits the directory enforces on the fields set above.
jq -e '.version == "'"$VERSION"'"
  and (.interface.displayName | length) <= 30
  and (.interface.shortDescription | length) <= 30
  and (.description | length) <= 4000
  and (.interface.defaultPrompt | all(length <= 128))' \
  "$STAGE/raystack/.codex-plugin/plugin.json" > /dev/null \
  || { echo "build-codex-zip: manifest breaks a directory limit" >&2; exit 1; }

ZIP="$OUT/raystack-codex-$VERSION.zip"
rm -f "$ZIP"
(cd "$STAGE/raystack" && zip -qr -X "$ZIP" . -x '.DS_Store' '*/.DS_Store')
echo "$ZIP"
