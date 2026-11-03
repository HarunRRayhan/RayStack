<h1><img src="assets/logo.svg" alt="" width="40" height="40" align="center"> RayStack</h1>

RayStack is a skill pack for coding agents that builds and reviews software. Type `/raystack`
in a repo and it works out what you want: take a product from idea to shipped code with
reviewed builds, or get a ranked findings report on cost, security, bottlenecks, deploys,
scaling or the database, with evidence for every finding and a fix you apply yourself. It's how
I build and what I check when I audit someone's stack, written down as agent skills.

By Harun R. Rayhan ([harun.dev](https://harun.dev), [@harundotdev](https://x.com/harundotdev)).
Product page: [harun.dev/raystack](https://harun.dev/raystack).

## Quick start

1. Paste this into Claude Code (or Codex, Cursor, Grok: change `claude` in the last line):

   ```text
   Install RayStack globally for claude. Run these two commands, then tell me the version it printed:
   git clone --depth 1 https://github.com/HarunRRayhan/RayStack.git ~/.raystack 2>/dev/null || git -C ~/.raystack pull --ff-only
   ~/.raystack/install.sh --agent claude
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

Every command and flow is explained in the **[guide](docs/guide.md)**.

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

### Install with a prompt

Paste one of these into your coding agent and it installs RayStack for you. Set the agent
name: `claude`, `codex`, `cursor`, `grok` or `opencode`.

**Global** (every project on this machine):

```text
Install RayStack globally for claude. Run these two commands, then tell me the version it printed:
git clone --depth 1 https://github.com/HarunRRayhan/RayStack.git ~/.raystack 2>/dev/null || git -C ~/.raystack pull --ff-only
~/.raystack/install.sh --agent claude
```

**This project only** (the skills go in the repo, so everyone who clones it gets them):

```text
Install RayStack into this project for claude. Run these two commands, then show me the new folder:
git clone --depth 1 https://github.com/HarunRRayhan/RayStack.git ~/.raystack 2>/dev/null || git -C ~/.raystack pull --ff-only
~/.raystack/install.sh --agent claude --project .
```

### Install from a terminal

```bash
git clone --depth 1 https://github.com/HarunRRayhan/RayStack.git ~/.raystack 2>/dev/null || git -C ~/.raystack pull --ff-only
~/.raystack/install.sh                      # global, Claude Code
~/.raystack/install.sh --agent codex        # global, another agent
```

### Install into an existing project

```bash
cd your-project
~/.raystack/install.sh --project            # Claude Code: ./.claude/skills
~/.raystack/install.sh --agent codex --project /path/to/repo
```

Commit the new folder so the whole team gets RayStack with the repo.

| Agent | Global folder | Project folder (`--project`) |
| --- | --- | --- |
| `claude` (default) | `~/.claude/skills` | `<repo>/.claude/skills` |
| `codex` | `~/.agents/skills` | `<repo>/.agents/skills` |
| `cursor` | `~/.cursor/skills` | `<repo>/.cursor/skills` |
| `grok` | `~/.grok/skills` | `<repo>/.claude/skills` (Grok reads it) |
| `opencode` | `~/.config/opencode/skills` | `<repo>/.opencode/skills` (unverified) |

A global install also makes the four principle skills (below) apply in every project on the
machine. Use `--project` if you only want RayStack in some repos.

Other options: `--dry-run` shows what would happen, `--link` symlinks to the checkout instead
of copying, `--agent custom --dir <folder>` installs anywhere, and `--help` lists the rest.

### Update

Type `/raystack update`, or run:

```bash
~/.raystack/install.sh --update
```

It pulls the latest release into `~/.raystack`, then refreshes every global and project
install made from it (they are listed in `~/.raystack-installs`). Start a new agent session
afterwards.

### Uninstall

```bash
~/.raystack/install.sh --uninstall                    # global
~/.raystack/install.sh --uninstall --project .        # this project
rm -rf ~/.raystack ~/.raystack-installs               # then the checkout and its list
```

`--uninstall` removes exactly the thirty RayStack skills and nothing else.

### Plugin installs

You can also install RayStack as a plugin instead of with `install.sh`. As a plugin, single
skills are namespaced: `/raystack` still works, but a review is `/raystack:frontend-review`
instead of `/frontend-review`.

| Agent | Install | Update |
| --- | --- | --- |
| Claude Code | `claude plugin marketplace add HarunRRayhan/RayStack` then `claude plugin install raystack@raystack` | `claude plugin marketplace update raystack` then `claude plugin update raystack@raystack` |
| Codex | `codex plugin marketplace add HarunRRayhan/RayStack` then `codex plugin add raystack@raystack` | `codex plugin marketplace upgrade raystack` then the `add` line again |
| Grok Build | `grok plugin install HarunRRayhan/RayStack --trust` | `grok plugin update raystack` |
| Cursor | `cursor-agent plugin marketplace add <gitUrl>` (unverified) | see [docs/agents.md](docs/agents.md) |

Or use the [skills CLI](https://skills.sh): `npx skills add HarunRRayhan/RayStack -g -a claude-code`.

Per-agent details, folders and sources: [docs/agents.md](docs/agents.md).

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
