# RayStack

RayStack is a pack of read-only infrastructure reviews for coding agents. Point your agent at a
repo, type `/raystack`, and you get a ranked findings report on cost, security, bottlenecks,
deploys, scaling or the database, with evidence for every finding and a fix you apply yourself.
It's what I check when I audit someone's stack, written down as agent skills.

By Harun R. Rayhan ([harun.dev](https://harun.dev), [@harundotdev](https://x.com/harundotdev)).

## Requirements

- `bash` and `jq`. The guard needs `jq` to read each command; without it, it blocks every
  shell command during a review (fails closed).
- For PDF export: Chrome or Chromium, and `npx` (Node.js).
- For blog covers: Chrome or Chromium and `node`, and the `raystack` skill installed beside
  `blog-cover` (`install.sh` and the plugin always do this). `sips` (macOS) or ImageMagick is optional,
  for a JPG.

## Install

### Any agent (one command)

```bash
npx skills add HarunRRayhan/raystack -g
```

The [skills CLI](https://skills.sh) finds the coding agents you have (Claude Code, Codex,
Cursor and others) and installs all sixteen skills globally for them. Add `-a claude-code` to pick
one agent. In Claude Code, the read-only guard works from `~/.claude/skills/`. A project-level
install (without `-g`) can't find it, so its reviews block every shell command.

The per-agent options below do the same thing in each agent's own way.

### Claude Code

```text
/plugin marketplace add HarunRRayhan/raystack
/plugin install raystack@raystack
```

From a terminal it's `claude plugin marketplace add HarunRRayhan/raystack` and
`claude plugin install raystack@raystack`. To try a checkout for one session:
`claude --plugin-dir /path/to/raystack`.

As a plugin, the skills are namespaced: `raystack:raystack`, `raystack:aws-billing-review` and
so on. `/raystack` still finds the router (it resolves to `/raystack:raystack`); name a single
review with its full name, e.g. `/raystack:aws-billing-review`. With `./install.sh --agent claude`
the skills are personal skills and keep their bare names (`/raystack`, `/aws-billing-review`).

### Codex

```bash
codex plugin marketplace add HarunRRayhan/raystack
codex plugin add raystack@raystack
```

Codex reads this repo's `.claude-plugin/marketplace.json`. Without a plugin,
`./install.sh --agent codex` copies the skills to `~/.agents/skills/`.

### Cursor

Add the repo as a git marketplace with `cursor-agent plugin marketplace add <gitUrl>`, or try it
for one session with `cursor-agent --plugin-dir /path/to/raystack`. Whether a git marketplace
picks up the `.claude-plugin/` files is **unverified**. If it doesn't,
`./install.sh --agent cursor` copies the skills to `~/.cursor/skills/`.

### Grok Build

```bash
grok plugin marketplace add HarunRRayhan/raystack
grok plugin install raystack --trust
```

`grok plugin validate .` passes on this repo, but these two commands are **unverified** end to
end. Grok also scans `~/.claude/skills/` and `~/.cursor/skills/`, so `install.sh` covers it.

### Any other agent

Clone the repo and copy (or `--link`) the skills into your agent's skills folder:

```bash
./install.sh --agent <claude|cursor|codex|grok|opencode>
./install.sh --agent custom --dir /path/to/skills
```

`--dry-run` shows what it would do and `--uninstall` removes exactly the sixteen RayStack skills.
A copy install points each review's guard hook at the installed guard. A `--link` install
can't, so in Claude Code its reviews block every shell command; use a copy install or
`claude --plugin-dir` there.
Per-agent details and sources are in [docs/agents.md](docs/agents.md).

## Run a review

Type `/raystack` in the repo you want reviewed. It looks at the file names (Terraform,
`railway.json`, migrations and so on), recommends reviews, and asks you once which ones to run
and whether it may make read-only live calls. Then it runs them one at a time.

Or skip the router and name a review: "run database-review", `/raystack:aws-billing-review`
(plugin) or `/aws-billing-review` (`install.sh`), or just "why is my AWS bill so high".

| Skill | What it reviews |
| --- | --- |
| `raystack` | Entry point. Picks the reviews for this repo and runs them. |
| `aws-billing-review` | AWS spend, with ranked savings in $/mo |
| `aws-security-review` | IAM, public exposure, logging and secrets on AWS |
| `aws-bottleneck-review` | Throttling, limits, quotas and single points on the AWS request path |
| `infra-review` | Deploys, rollback, backups, monitoring and exposure on any platform |
| `scaling-review` | What breaks first at 10x and 100x load |
| `database-review` | Queries, indexes, migrations, backups, connections and bloat |

With no live access, a review still works from your IaC and code. It marks those findings
`(unconfirmed)` and lists the exports or commands it needs from you.

## Reviews are read-only

No review changes anything live. Fixes come back as diffs or as commands for you to run.

Each review turns on a guard hook (`skills/raystack/hooks/readonly-guard.sh`) that checks every
shell command before it runs. Only the CLIs it lists are checked: `aws`, `gcloud`, `az`,
`kubectl`, `oc`, `terraform`, `tofu`, `terragrunt`, `helm`, `railway`, `wrangler`, `redis-cli`
and the SQL clients get read verbs only, one SQL read per call with no SQL comments. Deploy tools
such as `pulumi`, `cdk`, `serverless`, `fly`, `vercel` or `heroku` are blocked outright, as are
`pg_dump` and `pg_restore`, and commands that print secret values or credentials (for example
`terraform show`, `helm get values`, `aws ecr get-login-password`). A name counts even inside a
hyphenated or slashed word (`aws-cdk`, `amazon/aws-cli`). Package runners (`npx`, `bunx`, `uvx`),
shells (`bash`, `sh -c`, `env`), `ssh` and most `npm`, `yarn` and `docker` subcommands are blocked during
a review; only a short list of reads such as `docker ps`, `docker logs --tail 200` and `npm ls`
gets through. Reads that return env vars or user data (Lambda configs, ECS task definitions,
launch templates) are left for you to run.

Everything else is not checked: other tools, the agent's own file Read tool, and scripts in
the repo (a `make` target can do anything). The guard is a seatbelt, not a
sandbox, and it only switches on by itself in Claude Code. In Cursor, Codex and Grok the
reviews follow the same rules but nothing enforces them. Either way, run reviews with read-only
credentials (AWS `ReadOnlyAccess` or `ViewOnlyAccess`, a read-only DB role). Those are the real
boundary. The full rules are in [the review contract](skills/raystack/references/review-contract.md).

In Claude Code, once a review starts the guard stays on for the rest of the session. It then
also blocks `$`, backslashes, unquoted globs (`*`, `?`, `[ ]`) and redirects (`>`, `<`) in any
shell command, not only cloud ones. It also blocks any command that mentions a shell, `env`,
`ssh` or `scp`, a package runner (`npx`, `uv run`, `npm test` or other scripts, `yarn`, `pnpm`
and `bun` except `--version`), a container lifecycle command (`docker compose up`, `docker run`),
a docker flag before the subcommand, or a monitored tool's name anywhere (so `grep -n npm
Dockerfile` and `grep -rn "@aws-sdk" .` are blocked too). Start a new session after a review.

## What you get back

Each review writes `reviews/YYYY-MM-DD-<skill>.md` in your repo: an executive summary, the
inputs it used and the ones it lacked, findings ranked Critical to Low with evidence, a fix and an
estimated $/mo where one can be worked out, then a "Commands for you to run" section. The layout
is in [report-template.md](skills/raystack/references/report-template.md).

Want a PDF for a client or your boss? The review offers one at the end, via
`skills/raystack/scripts/report-pdf.sh` (needs Chrome or Chromium and `npx`). Raw HTML in a
report is shown as text, not rendered.

## Principles

RayStack also ships four principle skills. They aren't reviews. Each one is a short rule your
agent picks up by itself when the task fits, and `/raystack` never runs them.

| Skill | The rule |
| --- | --- |
| `principle-ship` | Done means live: PR, self-review, green CI, merge, deploy confirmed |
| `principle-smallest-change` | The smallest change that solves the whole task, finished everywhere it reaches |
| `principle-ask-with-question-tool` | Ask through the agent's question tool, batched, recommended option first |
| `principle-secrets-layout` | Real values in gitignored `.secrets/<service>.env`, committed `.example` templates, never print a value |

`principle-ship` reads `.raystack.json` at the repo root, or `~/.raystack.json` if the repo has
none:

```json
{ "ship": { "autoMerge": false, "deployCheck": "Deploy workflow on main, then GET /health" } }
```

With `autoMerge` off (the default), the agent stops at green CI and asks before it merges. Turn
it on and it merges on green, then waits for the deploy. `deployCheck` tells it how to confirm
the deploy is live: a workflow name, a URL or a health check.

## Content

RayStack also writes blog posts in your voice. Type `/blog`, or say "write a blog post". The flow
picks a topic, drafts the post, humanizes it and renders a cover. It stops at a draft and a
cover. It never publishes.

| Skill | What it does |
| --- | --- |
| `blog` | Entry point. Sets up your voice, then runs the flow. |
| `blog-topics` | Scores ideas from repo lessons, news and your ideas file. Shows the top 10, waits for your pick. |
| `blog-draft` | Writes the post as a draft in your voice, in the repo's post format |
| `humanize` | Rewrites AI-sounding prose so it reads like a person wrote it |
| `blog-cover` | Renders a cover image from an HTML card with headless Chrome. No AI images. |

### Your voice file

The first time you run `blog`, it sets up your voice: it reads 3 to 5 of your own posts and
writes a short style file. It looks for that file here, in order:

1. `.raystack/voice.md` at the repo root
2. `~/.raystack/voice.md`

The repo file wins. [skills/blog/references/voice-example.md](skills/blog/references/voice-example.md)
shows Harun's voice file as a worked example. It's there to show the shape. It is never used as
your voice.

## Credits

RayStack borrows ideas from four skill packs:

- [pstack](https://github.com/cursor/plugins/tree/main/pstack): short principle skills and
  step-by-step playbooks.
- [mattpocock/skills](https://github.com/mattpocock/skills): plain, composable skills.
- [gstack](https://github.com/garrytan/gstack): multi-agent installs, review skills and safety
  hooks that only switch on while their skill runs.
- [Ponytail](https://github.com/DietrichGebert/ponytail): the smallest complete change, and
  `shortcut:` comments for known limits.

`humanize` adapts Harun's own humanizer skill.

## License

MIT. See [LICENSE](LICENSE).

---

Made by [Harun R. Rayhan](https://harun.dev) ([@harundotdev](https://x.com/harundotdev)).
For a hands-on audit of your stack:
[harun.dev/consultation](https://harun.dev/consultation).
