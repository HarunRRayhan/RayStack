<p align="center"><img src="assets/logo.svg" alt="RayStack logo" width="88" height="88"></p>
<h1 align="center">RayStack</h1>

RayStack is a skill pack for coding agents that builds and reviews software. Type `/raystack`
in a repo and it works out what you want: take a product from idea to shipped code with
reviewed builds, or get a ranked findings report on cost, security, bottlenecks, deploys,
scaling or the database, with evidence for every finding and a fix you apply yourself. It's how
I build and what I check when I audit someone's stack, written down as agent skills.

By Harun R. Rayhan ([harun.dev](https://harun.dev), [@harundotdev](https://x.com/harundotdev)).
Product page: [harun.dev/raystack](https://harun.dev/raystack).

<p align="center"><a href="https://github.com/sponsors/HarunRRayhan"><img src="https://img.shields.io/badge/Sponsor-%E2%9D%A4-ea4aaa?logo=githubsponsors&logoColor=white" alt="Sponsor RayStack on GitHub Sponsors"></a></p>

## Quick start

1. Install RayStack for the coding agents on your machine. It finds them (Claude Code, Codex,
   Cursor, Grok, Antigravity, Gemini CLI, Copilot, Windsurf and more) and asks, for each one,
   whether to install there:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash
   ```

   Or paste this into your coding agent, and it installs for every agent it finds:

   ```text
   Install RayStack globally: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --yes`, then tell me which agents it installed for.
   ```

   For one agent only, or one project, see [Install](#install).
2. Start a new agent session, so it loads the skills.
3. In any repo, type one of these:

   | You want to | Type |
   | --- | --- |
   | Start a new product from an idea | `/raystack new project` |
   | Build a feature or fix a bug, planned and reviewed | `/raystack build <what>` or `/raystack fix <what>` |
   | Add missing docs (PRD, specs) to an existing repo | `/raystack project update` |
   | Get a read-only review of this repo | `/audit` (it suggests reviews) or `/audit security` |
   | Run several reviews as one job | `/audit all` |

Every command and flow is explained in the **[guide](docs/guide.md)**.

Requirements: `git`, `bash` and `jq`. In Claude Code the review guard needs `jq`: without it
every shell command is blocked during a review. PDF export also needs Chrome or Chromium and
Node.js (`npx`).

## What it does

**Build.** `/dev` (or `/raystack`) picks a track by the size of the work. A bug or small change (Quick) is
fixed, tested, reviewed and shipped. One slice of a feature (Standard) gets a spec, a plan and
a build. A new product (Full) goes through research, a PRD, architecture, specs, a plan and
the build. It asks you one question at a time, logs every answer in `DECISIONS.md` so it is
never asked twice, and stops for your approval at the PRD, spec and plan. The build runs task
by task with a fresh implementer and a fresh reviewer for each, then ships: PR, green CI,
merge, deploy confirmed.

**Review.** `/audit` is the entry point for reviews, as `/dev` is for building. On its own it
looks at the repo and recommends reviews; `/audit security` or `/audit database` runs one.
Reviews are read-only and write a ranked report to `reviews/` in your repo, each finding with
file:line evidence and a suggested fix. They never change your code or anything live.

| Review | What it looks at |
| --- | --- |
| `app-security-review` | Authorization and IDOR, injection, secrets, sessions, client IP spoofing, dependency risk |
| `cve-review` | Known CVEs in dependencies, and software that will collect them: end-of-life runtimes and frameworks, old base images, unpinned or vendored code, no update process |
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

**Scan.** `/audit all` or `/audit <type>` runs a set of reviews as one job with one round of
questions. Types: `security`, `performance`, `scalability`, `reliability`, `infra`, `aws`,
`database`, `cve`, `architecture`, `code`, `frontend` and `all`. When two or more reviews run, it also
writes one merged, ranked report. What each type runs is in the
[guide](docs/guide.md#scans).

**Fix.** Reviews never fix. Ask `/dev fix the findings in reviews/<report>.md` and the
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

Use a prompt (paste it into your agent) or the same command in a terminal. Either way it keeps
a checkout in `~/.raystack` that updates use later.

### Global (every agent on your machine)

```bash
curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash
```

[`get.sh`](get.sh) clones RayStack to `~/.raystack` (or updates it) and runs
`install.sh --agent all`. That looks in your home folder for each agent below and, at a
terminal, asks for each one it finds: `Install RayStack for Codex (~/.agents/skills)? [Y/n]`.
Run by an agent, or with `-s -- --yes`, it installs for all of them without asking. With none
found, it installs for Claude Code. Agents that read the same folder (Codex, Cline, Warp and
Zed all read `~/.agents/skills`) get one copy.

Prompt version:

```text
Install RayStack globally: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --yes`, then tell me which agents it installed for.
```

Rather not pipe a script into bash? Clone it and run the installer:

```bash
git clone --depth 1 https://github.com/HarunRRayhan/RayStack.git ~/.raystack
~/.raystack/install.sh --agent all
```

A global install also makes the four principle skills (below) apply in every project on the
machine. To install into one repo instead, add `--project .` to any command below; commit the
new skills folder and everyone who clones the repo gets RayStack.

### Agents

Open your agent for its prompt. Install for as many agents as you use. In a terminal, run the
command inside the backticks. Use the script or the agent's plugin, not both; as a plugin, a
single review is `/raystack:frontend-review` instead of `/frontend-review`.

<details>
<summary><img src="assets/agents/claude.png" alt="" width="16" height="16"> <b>Claude Code</b></summary>

```text
Install RayStack globally for Claude Code: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent claude`, then tell me what it printed.
```

Global folder `~/.claude/skills`, project folder `.claude/skills` (add `--project .`). Plugin instead: `claude plugin marketplace add HarunRRayhan/RayStack`, then `claude plugin install raystack@raystack` (update with `claude plugin marketplace update raystack` and `claude plugin update raystack@raystack`). Only Claude Code enforces the review guard.

</details>

<details>
<summary><img src="assets/agents/claude.png" alt="" width="16" height="16"> <b>Claude (desktop app)</b></summary>

```text
Install RayStack for Claude: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent claude`, then tell me what it printed.
```

Paste into the Code tab of the Claude desktop app, which is Claude Code: the skills go to `~/.claude/skills`.

</details>

<details>
<summary><img src="assets/agents/codex.png" alt="" width="16" height="16"> <b>Codex</b></summary>

```text
Install RayStack globally for Codex: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent codex`, then tell me what it printed.
```

Global folder `~/.agents/skills`, project folder `.agents/skills` (add `--project .`). Plugin instead: `codex plugin marketplace add HarunRRayhan/RayStack`, then `codex plugin add raystack@raystack` (update with `codex plugin marketplace upgrade raystack` and the `add` line again).

</details>

<details>
<summary><img src="assets/agents/chatgpt.png" alt="" width="16" height="16"> <b>ChatGPT (desktop app)</b></summary>

```text
Install RayStack for ChatGPT: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent codex`, then tell me what it printed.
```

Paste into Codex in the ChatGPT desktop app: the skills go to `~/.agents/skills`.

</details>

<details>
<summary><img src="assets/agents/cursor.png" alt="" width="16" height="16"> <b>Cursor</b></summary>

```text
Install RayStack globally for Cursor: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent cursor`, then tell me what it printed.
```

Global folder `~/.cursor/skills`, project folder `.cursor/skills` (add `--project .`). Plugin instead: `cursor-agent plugin marketplace add <gitUrl>` (unverified, see [docs/agents.md](docs/agents.md)).

</details>

<details>
<summary><img src="assets/agents/grok.png" alt="" width="16" height="16"> <b>Grok Build</b></summary>

```text
Install RayStack globally for Grok Build: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent grok`, then tell me what it printed.
```

Global folder `~/.grok/skills`, project folder `.claude/skills` (add `--project .`). Grok also reads `~/.claude/skills` and `~/.cursor/skills`, so a Claude Code or Cursor install already covers it. Plugin instead: `grok plugin install HarunRRayhan/RayStack --trust` (update with `grok plugin update raystack`).

</details>

<details>
<summary><img src="assets/agents/grok.png" alt="" width="16" height="16"> <b>Grok (app)</b></summary>

```text
Install RayStack for Grok: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent grok`, then tell me what it printed.
```

Paste into the Grok app, where it can run commands on your machine. The skills go to `~/.grok/skills`, which Grok Build reads too.

</details>

<details>
<summary><img src="assets/agents/antigravity.png" alt="" width="16" height="16"> <b>Antigravity</b></summary>

```text
Install RayStack globally for Antigravity: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent antigravity`, then tell me what it printed.
```

Global folder `~/.gemini/antigravity/skills`, project folder `.agents/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/gemini.png" alt="" width="16" height="16"> <b>Gemini CLI</b></summary>

```text
Install RayStack globally for Gemini CLI: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent gemini`, then tell me what it printed.
```

Global folder `~/.gemini/skills`, project folder `.agents/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/copilot.png" alt="" width="16" height="16"> <b>GitHub Copilot</b></summary>

```text
Install RayStack globally for GitHub Copilot: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent copilot`, then tell me what it printed.
```

Global folder `~/.copilot/skills`, project folder `.agents/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/windsurf.png" alt="" width="16" height="16"> <b>Windsurf</b></summary>

```text
Install RayStack globally for Windsurf: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent windsurf`, then tell me what it printed.
```

Global folder `~/.codeium/windsurf/skills`, project folder `.windsurf/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/cline.png" alt="" width="16" height="16"> <b>Cline</b></summary>

```text
Install RayStack globally for Cline: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent cline`, then tell me what it printed.
```

Global folder `~/.agents/skills`, project folder `.agents/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/kiro.png" alt="" width="16" height="16"> <b>Kiro</b></summary>

```text
Install RayStack globally for Kiro: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent kiro`, then tell me what it printed.
```

Global folder `~/.kiro/skills`, project folder `.kiro/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/roo.png" alt="" width="16" height="16"> <b>Roo Code</b></summary>

```text
Install RayStack globally for Roo Code: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent roo`, then tell me what it printed.
```

Global folder `~/.roo/skills`, project folder `.roo/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/kilo.png" alt="" width="16" height="16"> <b>Kilo Code</b></summary>

```text
Install RayStack globally for Kilo Code: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent kilo`, then tell me what it printed.
```

Global folder `~/.kilo/skills`, project folder `.agents/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/amp.png" alt="" width="16" height="16"> <b>Amp</b></summary>

```text
Install RayStack globally for Amp: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent amp`, then tell me what it printed.
```

Global folder `~/.config/agents/skills`, project folder `.agents/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/goose.png" alt="" width="16" height="16"> <b>Goose</b></summary>

```text
Install RayStack globally for Goose: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent goose`, then tell me what it printed.
```

Global folder `~/.config/goose/skills`, project folder `.goose/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/opencode.png" alt="" width="16" height="16"> <b>OpenCode</b></summary>

```text
Install RayStack globally for OpenCode: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent opencode`, then tell me what it printed.
```

Global folder `~/.config/opencode/skills`, project folder `.opencode/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/qwen.png" alt="" width="16" height="16"> <b>Qwen Code</b></summary>

```text
Install RayStack globally for Qwen Code: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent qwen`, then tell me what it printed.
```

Global folder `~/.qwen/skills`, project folder `.qwen/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/trae.png" alt="" width="16" height="16"> <b>Trae</b></summary>

```text
Install RayStack globally for Trae: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent trae`, then tell me what it printed.
```

Global folder `~/.trae/skills`, project folder `.trae/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/junie.png" alt="" width="16" height="16"> <b>Junie</b></summary>

```text
Install RayStack globally for Junie: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent junie`, then tell me what it printed.
```

Global folder `~/.junie/skills`, project folder `.junie/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/augment.png" alt="" width="16" height="16"> <b>Augment</b></summary>

```text
Install RayStack globally for Augment: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent augment`, then tell me what it printed.
```

Global folder `~/.augment/skills`, project folder `.augment/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/warp.png" alt="" width="16" height="16"> <b>Warp</b></summary>

```text
Install RayStack globally for Warp: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent warp`, then tell me what it printed.
```

Global folder `~/.agents/skills`, project folder `.agents/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/zed.png" alt="" width="16" height="16"> <b>Zed</b></summary>

```text
Install RayStack globally for Zed: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent zed`, then tell me what it printed.
```

Global folder `~/.agents/skills`, project folder `.agents/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/openhands.png" alt="" width="16" height="16"> <b>OpenHands</b></summary>

```text
Install RayStack globally for OpenHands: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent openhands`, then tell me what it printed.
```

Global folder `~/.openhands/skills`, project folder `.openhands/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/continue.png" alt="" width="16" height="16"> <b>Continue</b></summary>

```text
Install RayStack globally for Continue: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent continue`, then tell me what it printed.
```

Global folder `~/.continue/skills`, project folder `.continue/skills` (add `--project .`).

</details>

<details>
<summary><img src="assets/agents/openclaw.png" alt="" width="16" height="16"> <b>OpenClaw (Clawdbot)</b></summary>

```text
Install RayStack globally for OpenClaw: run `curl -fsSL https://raw.githubusercontent.com/HarunRRayhan/RayStack/main/get.sh | bash -s -- --agent openclaw`, then tell me what it printed.
```

Global folder `~/.openclaw/skills`, project folder `skills` (add `--project .`). Still on the old name? Use `--agent clawdbot` (`~/.clawdbot/skills`) or `--agent moltbot` (`~/.moltbot/skills`).

</details>

Not listed? `~/.raystack/install.sh --agent custom --dir /path/to/its/skills`, or the
[skills CLI](https://skills.sh): `npx skills add HarunRRayhan/RayStack -g -a <agent>`.

Claude Code, Codex, Cursor and Grok are tested with RayStack. The other folders come from the
skills CLI's agent table and are not tested here. The read-only review guard runs only in
Claude Code; on any other agent, give reviews read-only credentials. Logos belong to their
owners. Other options: `--dry-run` shows what would happen, `--link` symlinks to the checkout,
and `--help` lists the rest. Per-agent details and sources: [docs/agents.md](docs/agents.md).

## Update

Type `/raystack update` in your agent, or paste:

```text
Update RayStack: run `~/.raystack/install.sh --update`, then tell me the new version.
```

Or in a terminal:

```bash
~/.raystack/install.sh --update
```

It pulls the latest release into `~/.raystack`, then refreshes every global and project
install made from it (they are listed in `~/.raystack-installs`). Running the one-line install
again does the same for the agents it finds. Plugin installs update through the agent (see
above). Start a new agent session afterwards.

## Skills

RayStack is thirty-two skills. You only need `/raystack` (or `/dev` to build and `/audit` to review); they call the rest.

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
| 14 reviews | See [What it does](#what-it-does) |
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

## Uninstall

```text
Uninstall RayStack: run `~/.raystack/install.sh --uninstall --agent all`, then delete ~/.raystack and ~/.raystack-installs and tell me what was removed.
```

Or in a terminal:

```bash
~/.raystack/install.sh --uninstall --agent all          # every agent found
~/.raystack/install.sh --uninstall --project .          # this project (Claude Code)
rm -rf ~/.raystack ~/.raystack-installs                 # then the checkout and its list
```

`--uninstall` removes exactly the thirty-two RayStack skills and nothing else.

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

RayStack is free and MIT licensed. If it saves you time, you can
[sponsor it on GitHub](https://github.com/sponsors/HarunRRayhan).
