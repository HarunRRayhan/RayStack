# RayStack guide

How to use RayStack day to day.

## Install and update

Paste this into your coding agent (change `claude` to `codex`, `cursor`, `grok` or
`opencode`). Add `--project .` at the end of the second command to install into the current
repo instead of globally.

```text
Install RayStack for claude. Run these two commands, then tell me the version it printed:
git clone --depth 1 https://github.com/HarunRRayhan/RayStack.git ~/.raystack 2>/dev/null || git -C ~/.raystack pull --ff-only
~/.raystack/install.sh --agent claude
```

To update after a release, type `/raystack update`, or run `~/.raystack/install.sh --update`.
That refreshes every global and project install made from `~/.raystack`. More options
(plugins, per-agent folders) are in the [README](../README.md#install).

RayStack has one front door: `/raystack`. Type it with a few words and it routes you. There
are three things you can do:

1. **Start a new project**: questions, research, PRD, architecture, specs, plan, build.
2. **Work on an existing project**: fill missing docs, review the design mid-build, migrate
   part of the stack, or build the next feature.
3. **Review a codebase**: read-only reviews and scans, each a ranked report with a fix per
   finding.

## Cheat sheet

| You want to | Type |
| --- | --- |
| Start a new product | `/raystack new project` (or `/raystack project new`) |
| Add missing PRD, architecture, specs, plan to an existing repo | `/raystack project update` (or `project gaps`) |
| Check the architecture and plan against the code mid-build | `/raystack project review` |
| Move part of the project to another stack | `/raystack project migrate` |
| Build a feature or fix a bug the reviewed way | `/raystack build <what>` or `/raystack fix <what>` |
| See where a project stands | `/raystack where are we` |
| Review the architecture (MVC, CQRS, layers) | `/raystack review architecture` (or `review cqrs`, `review mvc`) |
| Review the frontend | `/raystack review frontend` |
| Find N+1 queries and slow endpoints | `/raystack review n+1` (or `review performance`) |
| Review the database | `/raystack review database` |
| Check reliability and availability | `/raystack review reliability` (or `review availability`) |
| Check what breaks at 10x load | `/raystack review scalability` |
| Check code health and tech debt | `/raystack review codebase` |
| Security review of the app code | `/raystack review security` |
| Review CI/CD and GitHub Actions | `/raystack review pipeline` |
| Review deploys, backups, rollback | `/raystack review infra` |
| Review AWS cost, security or bottlenecks | `/raystack review my AWS bill` (or `AWS security`, `AWS bottlenecks`) |
| Run several reviews as one job | `/raystack scan <type>` (see [Scans](#scans)) |
| Let RayStack suggest reviews for this repo | `/raystack` |
| Update RayStack to the latest release | `/raystack update` |

With a plugin install, a single skill is `/raystack:<name>`, e.g. `/raystack:frontend-review`.
With `install.sh` it is the bare name, e.g. `/frontend-review`.

## Start a new project

Run this in an empty folder (or a new repo):

```
/raystack new project
```

What happens, step by step. RayStack stops after each step for your approval.

1. **Intake.** Up to eight questions, one at a time, each with a recommended answer: what you
   are building, who it is for, the problem, what v1 must do, what it must never do, your
   limits (deadline, budget, stack you know, hosting, compliance), competitors, and how you
   will know it worked. Answer "not sure" when you are; it becomes an open item, not a guess.
2. **Project files.** `AGENTS.md`, `DECISIONS.md` and the `docs/` folders. Asks once whether
   the product is one repo or several.
3. **Research.** Notes on the market and on stack options, with a source beside every fact.
4. **PRD.** More questions, one at a time, until it can write goals, non-goals, anti-goals and
   numbered behaviours (`B-001` ...) that can each be tested.
5. **Architecture.** Settles the stack: language and framework, monolith or services, data
   store, hosting, auth/jobs/cache, repo layout. Defaults lean simple (one modular monolith,
   one relational database, a managed host). Each choice is logged with its reason.
6. **Tech specs.** One spec per area (data model, API, jobs, auth...), each naming the
   behaviours it serves.
7. **Plan.** Tasks for the first slice, each covering behaviours and naming its tests.
8. **Build.** A fresh agent builds each task and another reviews it. A ledger tracks progress,
   so a stopped build resumes where it left off. It ends in a PR, green CI and a merge.

Every answer you give lands in `DECISIONS.md` and is never asked again.

## Work on an existing project

**Fill the gaps.** In a repo that has code but no docs:

```
/raystack project update
```

It shows a table of what exists and what is missing or out of date (research, PRD,
architecture, specs, plan, decisions), then asks whether to fill all of it. It writes the
PRD from what the code does today, the architecture and specs as built, and asks you only
what code cannot tell (who it is for, goals, what it must never do). It writes documents
only, never code.

**Review the design mid-build.**

```
/raystack project review
```

Read-only. Checks the architecture, specs, plan and ledger against the code: parts the docs
name that the code lacks (and the reverse), decisions the code breaks, behaviours with no
task or test, over-design, tasks marked done with no commit. Writes
`reviews/YYYY-MM-DD-project-review.md`, and offers to replan.

**Migrate part of the stack.**

```
/raystack project migrate
```

Asks what part, to what (say, the pricing module to Rust), why, and your limits (downtime,
deadline, data). Then maps what the part does today, researches the target, and writes a
migration spec: the new part runs beside the old one, the same tests run against both, and
traffic moves in steps. The old code is deleted last. Then a plan, and the build after you
approve it.

**Build the next feature or fix a bug.** `/raystack build <feature>` or `/raystack fix <bug>`.
RayStack picks a track by size: Quick (fix, test, review, ship), Standard (spec, plan, build)
or Full (a new product).

## Review a codebase

Every review is read-only. It never edits code and never changes anything live. It writes a
report to `reviews/YYYY-MM-DD-<review>.md` with:

- an executive summary and the inputs it used or lacked;
- findings ranked Critical, High, Medium, Low, each with file:line evidence and a suggested fix;
- what it checked and found clean;
- commands for you to run when it needs something it is not allowed to run.

It offers a PDF at the end.

| Review | Looks at |
| --- | --- |
| `architecture-review` | Which pattern the code uses (MVC, layered, CQRS, hexagonal/DDD, modular monolith, microservices) and whether it is followed: fat controllers, a query side that writes, layer leaks, import cycles, god classes, shared databases between services |
| `frontend-review` | React, Next, Vue, Svelte, Angular, Inertia: component size, data fetching and waterfalls, re-renders, list keys, accessibility, forms and error states, bundle, SEO basics, unsafe HTML |
| `performance-review` | N+1 queries, unbounded queries, slow work in the request path, missing timeouts and caching, payload and bundle size |
| `database-review` | Queries, indexes, migrations, backups, connections, bloat (Postgres, MySQL, Redis, DynamoDB, SQLite) |
| `reliability-review` | Timeouts, retries, double charges and idempotency, queues and dead letters, graceful degradation, health checks, single points of failure, backups and restore, rollback, SLOs and alerts |
| `scaling-review` | What breaks first at 10x and 100x load |
| `codebase-review` | Test gaps on core paths, big files that change often, dead code, duplicated business rules, swallowed errors, outdated or abandoned dependencies |
| `app-security-review` | Authorization and IDOR, injection, secrets in code and git history, sessions, security logging, vulnerable dependencies |
| `pipeline-security-review` | GitHub Actions and GitLab CI, pinned actions, workflow permissions, Dockerfiles, IaC, lockfiles and supply chain |
| `infra-review` | Deploys, rollback, backups, monitoring and exposure on any platform |
| `aws-billing-review`, `aws-security-review`, `aws-bottleneck-review` | AWS spend ($/mo savings), IAM and exposure, throttling and limits |

**Live access.** Some reviews can read a live database or cloud account, only after you say
yes, and only with read-only access. Say no and they work from the code and config, marking
findings that need live data as `(unconfirmed)`. For AWS, `aws-readonly-setup` creates a
read-only profile.

**Fixing findings.** Reviews never fix. To act on a report, ask RayStack to fix it
(`/raystack fix the findings in reviews/...`). Fixes then go through the reviewed build flow.

## Scans

`/raystack scan <type>` runs several reviews as one job. It asks its questions once at the
start, skips reviews with nothing to look at, and writes one ranked summary,
`reviews/YYYY-MM-DD-scan-<type>.md`, next to each review's own report.

| Type | Runs |
| --- | --- |
| `security` | app security, pipeline security, AWS security, infra |
| `performance` | performance, database, AWS bottlenecks |
| `scalability` | scaling, database |
| `reliability` | reliability, database, scaling, infra |
| `architecture` | architecture, codebase |
| `code` | codebase, architecture, frontend |
| `frontend` | frontend, performance |
| `infra` | infra, pipeline security, AWS security, AWS bottlenecks |
| `aws` | the three AWS reviews |
| `database` | database |
| `all` | every review that fits the repo |

## What RayStack writes

| Path | What |
| --- | --- |
| `DECISIONS.md` | Every decision, dated, with how to confirm it. Never asked twice |
| `AGENTS.md` | How agents should work in this repo |
| `docs/research/` | Dated research notes |
| `docs/prd/` | The PRD and its numbered behaviours |
| `docs/architecture/` | System overview with the Stack table |
| `docs/tech-spec/` | One spec per area, plus migration specs |
| `docs/plans/` | Plans and their ledgers |
| `reviews/` | Review and scan reports |

## Safety

- Reviews run behind a guard (in Claude Code) that blocks any shell command that could
  change something: only read forms of git, cloud CLIs, database clients and scanners pass.
- Scanners (gitleaks, semgrep, osv-scanner, zizmor, actionlint, hadolint) run only when you
  have installed them. RayStack never installs anything.
- Secrets: reviews never open `.env` files or print secret values.

## Troubleshooting

- **"guard missing" or every command blocked:** install `jq`; the guard needs it.
- **A command is not found:** with a plugin install, prefix skills with `raystack:`.
- **It asked the same question twice:** check `DECISIONS.md`. A settled row is never asked
  again; if it is missing there, the answer was not logged.
- **A build stopped:** run `/raystack where are we`. It resumes from the ledger.
