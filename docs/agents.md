# Agent support

RayStack ships the same eighteen skills (`skills/<name>/SKILL.md`) to every agent. Each agent gets
a manifest only when it has a documented plugin format. Researched 2026-10-28. Anything marked
**unverified** was not confirmed against official docs or a local run.

| Agent | Manifest in this repo | Read-only guard |
| --- | --- | --- |
| Claude Code | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | Automatic, scoped to an active review |
| Cursor | `.cursor-plugin/plugin.json` | Not automatic |
| OpenAI Codex | `plugin.json` (repo root), reuses `.claude-plugin/marketplace.json` | Not automatic |
| xAI Grok Build | none of its own, reads `.claude-plugin/` | Not automatic |

Every manifest `version` equals `VERSION`. `tests/check-versions.sh` checks this.

## Claude Code

**Install**

```bash
claude plugin marketplace add HarunRRayhan/raystack
claude plugin install raystack@raystack
```

To try a checkout for one session without installing: `claude --plugin-dir /path/to/raystack`.
Skills then show as `raystack:<name>`, for example `/raystack:aws-billing-review`; `/raystack`
also resolves to `raystack:raystack` (confirmed in a `--plugin-dir` session). A plugin install
namespaces the same way.

**Files**

- `.claude-plugin/plugin.json`: `name`, `version`, `description`, `author` (`name`, `url`),
  `homepage`, `repository`, `license`, `keywords`, `skills: "./skills/"`. All are documented
  manifest fields. `skills` adds to the default `skills/` scan, so it is explicit, not required.
- `.claude-plugin/marketplace.json`: `name`, `owner`, `description`, and one plugin entry with
  `source: "./"` (the repo root is the plugin). The entry repeats `version`; `plugin.json` wins
  if they ever differ, and `claude plugin validate` warns on a mismatch.

**Skill discovery:** `<plugin>/skills/<name>/SKILL.md`. Claude loads name and description up
front and the body when the skill runs.

**Hooks:** Supported in SKILL.md frontmatter (`hooks:`), same shape as settings hooks. A skill
hook registers when the skill is invoked and stays on for the rest of the session. Each review
skill declares:

```yaml
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'for f in "${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh" "${CLAUDE_PLUGIN_ROOT}/../raystack/hooks/readonly-guard.sh" "$HOME/.claude/skills/raystack/hooks/readonly-guard.sh"; do [ -x "$f" ] && exec "$f"; done; echo "RayStack review is read-only: guard missing" >&2; exit 2'
```

In a plugin, `${CLAUDE_PLUGIN_ROOT}` is the plugin root (confirmed with `claude --plugin-dir`).
For an installed skill (`~/.claude/skills/`, a project's `.claude/skills/`, `install.sh`, or
`npx skills add`), Claude Code sets it to the skill's own folder (confirmed in Claude Code
2.1.312), so the guard is found in the sibling `raystack` skill. `~/.claude/skills/raystack` is
the last fallback. The command fails closed: a hook that exits with anything other than 2 does
not block, so a missing guard exits 2 on purpose and every shell command is blocked until the
install is fixed. The paths are quoted because they may hold spaces. The hook gets `.tool_input.command` on stdin; exit 2 blocks and
stderr is the reason.

The hook stays on after the review turn, for the rest of the session. It keeps checking every
shell command: mutating cloud/DB calls stay blocked, and so do `$`, backticks, backslashes,
unquoted globs (`*`, `?`, `[ ]`), braces and redirects (`>`, `<`) in any command, cloud or not.
Start a new session after a review.

**Sources**

- https://code.claude.com/docs/en/plugins-reference (plugin.json fields, `${CLAUDE_PLUGIN_ROOT}`)
- https://code.claude.com/docs/en/plugins/marketplace-reference (marketplace.json)
- https://code.claude.com/docs/en/skills (frontmatter fields, including `hooks`)
- https://code.claude.com/docs/en/hooks (hooks in skills, PreToolUse input, exit 2)

## Cursor

**Install:** Cursor plugins are published through the Cursor marketplace
(https://cursor.com/marketplace/publish) or a git marketplace added with
`cursor-agent plugin marketplace add <gitUrl>`. For one session: `cursor-agent --plugin-dir
/path/to/raystack`. Whether a git marketplace needs a `.cursor-plugin/marketplace.json` or also
reads `.claude-plugin/marketplace.json` is **unverified**; this repo ships no Cursor marketplace
file. Without a plugin, `install.sh --agent cursor` copies the skills to
`~/.cursor/skills/`.

**Files:** `.cursor-plugin/plugin.json`, mirroring pstack: `name`, `displayName`, `version`,
`description`, `author`, `homepage`, `repository`, `license`, `keywords`, `skills: "./skills/"`.
Only `name` is required. `displayName` is not in the official field list but pstack and other
cursor/plugins manifests use it.

**Skill discovery:** `skills/<name>/SKILL.md`, frontmatter `name` and `description`.

**Hooks:** Plugins can ship `hooks/hooks.json` (events include `beforeShellExecution` and
`preToolUse`). Skill frontmatter hooks are not documented, so the guard does not turn on when a
review starts. `preToolUse` sends `.tool_input.command`, and exit 2 blocks, so the guard script
works if a user wires it in by hand. A plugin-level hook would run in every session, not only
during reviews, so RayStack does not ship one.

**Sources**

- https://cursor.com/docs/reference/plugins
- https://cursor.com/docs/agent/hooks
- https://github.com/cursor/plugins (pstack `.cursor-plugin/plugin.json`)

## OpenAI Codex

**Install**

```bash
codex plugin marketplace add HarunRRayhan/raystack
codex plugin add raystack@raystack
```

Codex 0.165.0 reads `.claude-plugin/marketplace.json` from this repo and installs the plugin
(confirmed in a run with a throwaway `CODEX_HOME`). The documented Codex marketplace path is
`.agents/plugins/marketplace.json`; this repo does not need one.

Without a plugin, Codex loads skills from `~/.agents/skills/<name>/SKILL.md` (user) and
`.agents/skills/` (repo). The docs do not list `~/.codex/skills`. `install.sh --agent codex`
uses `~/.agents/skills/`.

**Files:** `plugin.json` at the repo root, the portable Agent Plugins manifest Codex prefers
(`$schema`, `name`, `version`, `description`, `author`, `homepage`, `repository`, `license`,
`keywords`). Skills are found in the root `skills/` directory. `.codex-plugin/plugin.json` is a
documented fallback and is not needed. Per-skill `agents/openai.yaml` (what mattpocock ships) is
optional UI metadata (`interface.display_name`, `policy.allow_implicit_invocation`, tool
dependencies); RayStack does not need it.

**Skill discovery:** `name` and `description` are required in frontmatter. Codex loads name,
description and path up front and reads the body when it uses the skill. Other frontmatter
keys, including `hooks:`, are ignored as far as the docs say.

**Hooks:** Codex supports `PreToolUse` for `Bash` in `~/.codex/hooks.json`,
`<repo>/.codex/hooks.json`, `config.toml`, or a plugin's `hooks/hooks.json`. Input is
`.tool_input.command`, the same as Claude, and exit 2 blocks with stderr as the reason. Codex
also sets `CLAUDE_PLUGIN_ROOT` for plugin hooks. Skills cannot declare hooks, and plugin hooks
are not trusted until the user enables them and would run in every session, so the guard does
not turn on automatically during a Codex review.

**Sources**

- https://learn.chatgpt.com/docs/build-skills (redirect from developers.openai.com/codex/skills)
- https://developers.openai.com/codex/plugins/build
- https://learn.chatgpt.com/docs/hooks (redirect from developers.openai.com/codex/hooks)

## xAI Grok Build

xAI's coding agent is Grok Build (`grok` CLI). https://x.ai/bot returns 403 to a plain fetch;
the facts below come from the user guide in the open-source repo.

**Install**

```bash
grok plugin marketplace add HarunRRayhan/raystack
grok plugin install raystack --trust
```

Grok reads `.grok-plugin/marketplace.json` and also accepts the `.claude-plugin/` files, so it
needs no manifest of its own. `grok plugin validate .` passes on this repo (grok 1.0.70). The
install commands above follow the docs but were not run (**unverified** end to end).

Without a plugin, Grok scans `~/.grok/skills/`, `.grok/skills/`, and by default
`~/.claude/skills/` and `~/.cursor/skills/`, so `install.sh` covers it too.

**Skill discovery:** `skills/<name>/SKILL.md`. Frontmatter `name`, `description`, plus optional
`when-to-use`, `allowed-tools`, `disable-model-invocation`, `model`, `effort`, `license`,
`compatibility`, `metadata`. `hooks` is not a documented skill field.

**Hooks:** JSON files under `~/.grok/hooks/`, `.grok/hooks/`, Claude settings files, or a
plugin's `hooks/hooks.json`. `PreToolUse` input is camelCase: `.toolInput.command` with
`toolName: "run_terminal_command"`. The guard reads `.toolInput.command` when
`.tool_input.command` is absent (tested in `tests/test-guard.sh`). Exit 2 denies. Plugin hooks
get `GROK_PLUGIN_ROOT` and Claude aliases. Skills cannot declare hooks, so the guard does not
turn on automatically during a Grok review.

**Sources**

- https://github.com/xai-org/grok-build/tree/main/crates/codegen/xai-grok-pager/docs/user-guide
  (`08-skills.md`, `09-plugins.md`, `10-hooks.md`)
- https://x.ai/news/grok-build-cli

## Read-only outside Claude Code

Only Claude Code turns the guard on by itself. In Cursor, Codex and Grok the review still
follows the contract's read-only rules, but nothing enforces them. Run reviews there with
read-only credentials, which the contract asks for anyway.
