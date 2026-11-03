# Publishing RayStack to plugin directories

RayStack installs from GitHub today (see the README). These directories list it where people
browse. Each needs a submission from the maintainer's signed-in account.

| Directory | Where | Updates after listing |
| --- | --- | --- |
| Claude (community marketplace) | https://claude.ai/directory/manage | Automatic from `main` |
| Cursor Marketplace | https://cursor.com/marketplace/publish | Reviewed; ask marketplace-publishing@cursor.com |
| cursor.directory | https://cursor.directory | Managed on the site |
| OpenAI / Codex | https://platform.openai.com/plugins | Upload a new ZIP per release |
| skills.sh | Listed on its own from `npx skills` installs | Automatic |

## Paste-ready text

- **Name:** RayStack (`raystack`)
- **Short (30 chars):** Plan, build and review code
- **One line:** One `/raystack` command to start a project, improve an existing one, or run
  read-only reviews and scans.
- **Long:** the `description` in `plugin.json`.
- **Repository:** https://github.com/HarunRRayhan/RayStack
- **Website:** https://harun.dev/raystack
- **Support:** https://github.com/HarunRRayhan/RayStack/issues
- **License:** MIT
- **Logo:** `assets/logo.png` (512x512), `assets/logo.svg`
- **Example prompts:** `/raystack new project`, `/raystack project review`, `/raystack scan all`

## Claude

1. `claude plugin validate .` (passes).
2. In the portal: **Submit new**, **Plugin bundle**, repository `HarunRRayhan/RayStack`, leave
   the path and branch empty, **Validate**.
3. Data handling: no personal data collected or stored by RayStack; it sends nothing to any
   service of its own (web research uses the agent's own search tools); reports stay in the
   user's repo; not aimed at under-18s. Reviews read a live database or cloud account only
   when the user says yes, and only read-only.
4. Updates: **GitHub push webhook**. Each release already raises `version`.

Listed plugins install with `claude plugin install raystack@claude-community`.

## Cursor

Submit the repository link at the publish page. `.cursor-plugin/plugin.json` has the name,
description, logo and `skills` path; the README documents usage. The form submits under the
signed-in person, not a company. Do not resubmit while it waits: that adds a duplicate.

## OpenAI / Codex

1. `bash scripts/build-codex-zip.sh` writes `dist/raystack-codex-<version>.zip`. It adds a
   `.codex-plugin/plugin.json` with the listing fields, only inside the ZIP. The ZIP installs
   in Codex with all skills (tested with a local marketplace and a throwaway `CODEX_HOME`).
2. **Upload new or existing plugin**, pick the verified developer identity, upload the ZIP,
   fix any findings, **Submit for review**.
3. Each release: build and upload the new ZIP.

Unknown until the first upload: whether the dashboard accepts `Productivity` as the
category, and whether it objects to the `hooks:` key in some skills' frontmatter (Codex
ignores it; plugin-level hooks are what the directory rejects).
