# Update RayStack

For `/raystack update`, "update raystack" or "which version". Never update without saying
what will run, and never touch files outside the RayStack install targets.

## 1. Find the installed version and how it was installed

Read `.raystack-installed` in this skill's folder (the folder holding this skill's
`SKILL.md`):

- It exists: line 1 is the version. A `source=<path>` line names the checkout it came from:
  an `install.sh` install.
- It does not exist and the skill path sits under `~/.claude/plugins/`,
  `~/.codex/plugins/cache/` or `~/.grok/installed-plugins/`: a plugin install. The version is
  in the plugin's `plugin.json` (or `VERSION`).
- Neither: an `npx skills` install, or a copy made by hand.

## 2. Find the latest release

`gh release view -R HarunRRayhan/RayStack --json tagName -q .tagName`, or
`curl -s https://api.github.com/repos/HarunRRayhan/RayStack/releases/latest | jq -r .tag_name`.
If both fail, say so and go on with the update command anyway.

Tell the user both versions. If they match, say it is up to date and stop.

## 3. Update

| Installed by | Run |
| --- | --- |
| `install.sh` (`source=<path>`) | `<path>/install.sh --update` (pulls, then refreshes every global and project install made from that checkout) |
| `install.sh`, no `source=` line (before 0.9.2) | `~/.raystack/install.sh --update` if `~/.raystack` exists; else clone it as in the README, then run `install.sh --update` once |
| Claude Code plugin | `claude plugin marketplace update raystack` then `claude plugin update raystack@raystack` |
| Codex plugin | `codex plugin marketplace upgrade raystack` then `codex plugin add raystack@raystack` |
| Cursor plugin | `cursor-agent plugin marketplace update raystack` (unverified) |
| Grok plugin | `grok plugin update raystack` (the name may carry a suffix; `grok plugin list` shows it) |
| `npx skills` | `npx skills add HarunRRayhan/RayStack -g -a <agent>` again |

Run the command, show its last lines and the new version. Then tell the user to start a new
agent session so the updated skills load. The release notes are at
`https://github.com/HarunRRayhan/RayStack/releases`.
