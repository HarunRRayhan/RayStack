<h1><img src="assets/logo.svg" alt="" width="40" height="40" align="center"> RayStack</h1>

RayStack is a skill pack for coding agents that builds and reviews software. Type `/raystack`
in a repo and it works out what you want: take a product from idea to shipped code with
reviewed builds, or get a ranked findings report on cost, security, bottlenecks, deploys,
scaling or the database, with evidence for every finding and a fix you apply yourself. It's how
I build and what I check when I audit someone's stack, written down as agent skills.

By Harun R. Rayhan ([harun.dev](https://harun.dev), [@harundotdev](https://x.com/harundotdev)).
Product page: [harun.dev/raystack](https://harun.dev/raystack).

## Quick start

1. Install it for every coding agent on your machine (Claude Code, Codex, Cursor, Grok,
   OpenCode):

   ```bash
   curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash
   ```

2. Start a new agent session, so it loads the skills.
3. In any repo, type one of these:

   | You want to | Type |
   | --- | --- |
   | Start a new product from an idea | `/raystack new project` |
   | Build a feature or fix a bug, planned and reviewed | `/raystack build <what>` or `/raystack fix <what>` |
   | Add missing docs (PRD, specs) to an existing repo | `/raystack project update` |
   | Get a read-only review of this repo | `/raystack` (it suggests reviews) or `/raystack review security` |
   | Run several reviews as one job | `/raystack scan all` |

Every command and flow is explained in the **[guide](docs/guide.md)**. Only one agent, or
installing into a single repo? See [Install](#install).

Requirements: `git`, `bash` and `jq`. In Claude Code the review guard needs `jq`: without it
every shell command is blocked during a review. PDF export also needs Chrome or Chromium and
Node.js (`npx`).

## What it does

**Build.** `/raystack` picks a track by the size of the work. A bug or small change (Quick) is
fixed, tested, reviewed and shipped. One slice of a feature (Standard) gets a spec, a plan and
a build. A new product (Full) goes through research, a PRD, architecture, specs, a plan and
the build. It asks you one question at a time, logs every answer in `DECISIONS.md` so it is
never asked twice, and stops for your approval at the PRD, spec and plan. The build runs task
by task with a fresh implementer and a fresh reviewer for each, then ships: PR, green CI,
merge, deploy confirmed.

**Review.** Read-only reviews write a ranked report to `reviews/` in your repo, each finding
with file:line evidence and a suggested fix. They never change your code or anything live.

| Review | What it looks at |
| --- | --- |
| `app-security-review` | Authorization and IDOR, injection, secrets, sessions, client IP spoofing, dependency risk |
| `pipeline-security-review` | CI/CD: workflow permissions, untrusted input, pinned actions, Dockerfiles, supply chain |
| `infra-review` | Deploys, rollback, backups, monitoring and exposure on any platform (Railway, Cloudflare, VPS, Kubernetes, AWS, GCP, Azure) |
| `performance-review` | N+1 queries, hot paths, blocking calls, caching, payload and bundle weight |
| `database-review` | Queries, indexes, migrations, backups, connections and bloat (Postgres, MySQL, Redis, DynamoDB, SQLite) |
| `reliability-review` | Timeouts, retries, idempotency, double charges, queues, health checks, single points of failure, SLOs |
| `scaling-review` | What breaks first at 10x and 100x load |
| `architecture-review` | Whether the code follows its pattern (MVC, layered, CQRS, hexagonal, modular monolith, microservices) |
| `frontend-review` | React, Next, Vue, Svelte, Angular, Inertia: components, data fetching, re-renders, accessibility, forms, bundle |
| `codebase-review` | Test gaps, complexity hot spots, dead code, duplication, swallowed errors, outdated dependencies |
| `aws-billing-review` | AWS spend, with ranked savings per month |
| `aws-security-review` | IAM, public exposure, logging and secrets on AWS |
| `aws-bottleneck-review` | Throttling, limits, quotas and single points on the AWS request path |

With no live access, a review works from your code and config and marks findings that need
live data `(unconfirmed)`. Each report ends with the commands it needs you to run.

**Scan.** `/raystack scan <type>` runs a set of reviews as one job with one round of
questions. Types: `security`, `performance`, `scalability`, `reliability`, `infra`, `aws`,
`database`, `architecture`, `code`, `frontend` and `all`. When two or more reviews run, it also
writes one merged, ranked report. What each type runs is in the
[guide](docs/guide.md#scans).

**Fix.** Reviews never fix. Ask `/raystack fix the findings in reviews/<report>.md` and the
fixes go through the build flow.

## Safety

- Reviews are read-only. Fixes come back as diffs or commands for you to run.
- Every live call (a database, a cloud account, a dependency audit) is asked for first. Say no
  and nothing outside your repo is read.
- In Claude Code a guard hook checks every shell command during a review and blocks writes
  to clouds, databases and deploy tools. It is a seatbelt, not a sandbox: other tools and
  repo scripts are not checked, and other agents don't enforce it. Give reviews read-only
  credentials; `aws-readonly-setup` creates a read-only AWS profile for you. The six
  scanners (gitleaks, semgrep, osv-scanner, zizmor, actionlint, hadolint) run when installed;
  RayStack never installs them.
- **After a review, start a new session before you build or run tests.** The guard stays on
  for the rest of the session and blocks things like `npm test` and `$` in commands.
- RayStack has no server and collects nothing. Your agent sends your code to its own model,
  as it always does.

Details, read-only credentials per database and platform, and privacy:
[docs/safety.md](docs/safety.md).

## Install

### Every agent at once

```bash
curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash
```

[`get.sh`](get.sh) clones RayStack to `~/.raystack` (or updates it), then runs
`install.sh --agent all`. That installs the thirty skills for each agent it finds in your home
folder: `~/.claude`, `~/.codex`, `~/.cursor`, `~/.grok`, `~/.config/opencode`. With none
found, it installs for Claude Code. Grok gets no copy of its own when Claude Code or Cursor is
there, because it reads their skills folders.

Arguments after `bash -s --` go to `install.sh`:

```bash
curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --project .         # this repo, for every agent found
curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent codex      # one agent
```

Rather not pipe a script into bash? Same result:

```bash
git clone --depth 1 https://github.com/HarunRRayhan/RayStack.git ~/.raystack
~/.raystack/install.sh --agent all
```

Or paste this into any coding agent:

```text
Install RayStack: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash`, then tell me which agents it installed for.
```

A project install (`--project`) puts the skills in the repo. Commit that folder and everyone
who clones the repo gets RayStack. A global install also makes the four principle skills
(below) apply in every project on the machine; use `--project` if you want RayStack only in
some repos.

### One agent

Each agent can use the script (copies the skills into its folder) or, for most, its own plugin
system. Use one or the other, not both. As a plugin, single skills are namespaced: `/raystack`
still works, but a review is `/raystack:frontend-review` instead of `/frontend-review`.

**Claude Code**

- Script: `~/.raystack/install.sh --agent claude` puts the skills in `~/.claude/skills`; with
  `--project` in `<repo>/.claude/skills`.
- Plugin: `claude plugin marketplace add HarunRRayhan/RayStack`, then
  `claude plugin install raystack@raystack`. Update with `claude plugin marketplace update
  raystack` and `claude plugin update raystack@raystack`.
- Only Claude Code enforces the review guard.

**Codex**

- Script: `~/.raystack/install.sh --agent codex` puts the skills in `~/.agents/skills`; with
  `--project` in `<repo>/.agents/skills`.
- Plugin: `codex plugin marketplace add HarunRRayhan/RayStack`, then
  `codex plugin add raystack@raystack`. Update with `codex plugin marketplace upgrade raystack`
  and the `add` line again.

**Cursor**

- Script: `~/.raystack/install.sh --agent cursor` puts the skills in `~/.cursor/skills`; with
  `--project` in `<repo>/.cursor/skills`.
- Plugin: `cursor-agent plugin marketplace add <gitUrl>` (unverified; see
  [docs/agents.md](docs/agents.md)).

**Grok Build**

- Script: Grok reads `~/.claude/skills` and `~/.cursor/skills`, so a Claude Code or Cursor
  install already covers it. Otherwise `~/.raystack/install.sh --agent grok` puts the skills in
  `~/.grok/skills`; with `--project` in `<repo>/.claude/skills`.
- Plugin: `grok plugin install HarunRRayhan/RayStack --trust`. Update with
  `grok plugin update raystack`.

**OpenCode**

- Script: `~/.raystack/install.sh --agent opencode` puts the skills in
  `~/.config/opencode/skills`; with `--project` in `<repo>/.opencode/skills` (unverified).

**Any other agent**

- `~/.raystack/install.sh --agent custom --dir /path/to/its/skills`
- Or the [skills CLI](https://skills.sh): `npx skills add HarunRRayhan/RayStack -g -a claude-code`
  (change the agent name).

The `~/.raystack/install.sh` lines need the checkout: run the one-line install first, or
`git clone --depth 1 https://github.com/HarunRRayhan/RayStack.git ~/.raystack`.
Other options: `--dry-run` shows what would happen, `--link` symlinks to the checkout
instead of copying, and `--help` lists the rest. Per-agent details and sources:
[docs/agents.md](docs/agents.md).

### Update

Type `/raystack update` in your agent, or run:

```bash
~/.raystack/install.sh --update
```

It pulls the latest release into `~/.raystack`, then refreshes every global and project
install made from it (they are listed in `~/.raystack-installs`). Running the one-line install
again does the same for the agents it finds. Plugin installs update through the agent (see
above). Start a new agent session afterwards.

### Uninstall

```bash
~/.raystack/install.sh --uninstall --agent all          # every agent's global folder
~/.raystack/install.sh --uninstall --project .          # this project (Claude Code)
rm -rf ~/.raystack ~/.raystack-installs                 # then the checkout and its list
```

`--uninstall` removes exactly the thirty RayStack skills and nothing else.

## Skills

RayStack is thirty skills. You only need `/raystack`; it calls the rest.

| Skill | What it does |
| --- | --- |
| `raystack` | The entry point. Routes to the dev flow, a review, a scan or an update |
| `dev` | Picks the Quick, Standard or Full track and runs the right steps |
| `dev-hub` | Sets up `AGENTS.md`, `DECISIONS.md` and the docs folders, in one repo or a code-free hub for several repos |
| `dev-research` | Dated research notes with a source beside every fact |
| `dev-prd` | Interviews you, then writes the PRD (product requirements) with goals, non-goals and numbered, testable behaviours |
| `dev-spec` | The architecture and a tech spec per area |
| `dev-plan` | A plan for one slice of work, checked for gaps before the build |
| `dev-build` | Builds the plan task by task with a fresh implementer and reviewer for each, then ships |
| `dev-gaps` | Finds the docs an existing project is missing and writes them from the code and your answers |
| `dev-review` | Read-only check of the architecture, specs and plan against the code |
| `dev-migrate` | Moves part of a project to another language, framework or database, step by step with parity tests |
| 13 reviews | See [What it does](#what-it-does) |
| `aws-readonly-setup` | Creates a read-only AWS profile for the AWS reviews |
| `local-verify` | Checks a user-facing change in a real local browser before it ships |
| `principle-ship` | Done means live: PR, self-review, green CI, merge, deploy confirmed |
| `principle-smallest-change` | The smallest change that solves the whole task |
| `principle-ask-with-question-tool` | Ask through the agent's question tool, recommended option first |
| `principle-secrets-layout` | Real values in gitignored `.secrets/<service>.env`, committed `.example` templates |

The principle skills load by themselves whenever a task fits, in any project where RayStack
is installed. `principle-ship` reads `.raystack.json` at the repo root, or `~/.raystack.json`:

```json
{ "ship": { "autoMerge": false, "deployCheck": "Deploy workflow on main, then GET /health" } }
```

With `autoMerge` off (the default) the agent stops at green CI and asks before it merges.
`deployCheck` tells it how to confirm the deploy is live. A repo with no git remote is merged
locally after you say yes.

## Credits

RayStack borrows ideas from four skill packs:

- [pstack](https://github.com/cursor/plugins/tree/main/pstack): short principle skills and
  step-by-step playbooks.
- [mattpocock/skills](https://github.com/mattpocock/skills): plain, composable skills.
- [gstack](https://github.com/garrytan/gstack): multi-agent installs, review skills and safety
  hooks that only switch on while their skill runs.
- [Ponytail](https://github.com/DietrichGebert/ponytail): the smallest complete change, and
  `shortcut:` comments for known limits.

## License

MIT. See [LICENSE](LICENSE).

---

Made by [Harun R. Rayhan](https://harun.dev) ([@harundotdev](https://x.com/harundotdev)).
For a hands-on audit of your stack:
[harun.dev/consultation](https://harun.dev/consultation).
