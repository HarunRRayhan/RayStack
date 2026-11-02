---
name: reliability-review
description: Read-only reliability and availability review of the application code and deploy config with a ranked findings report. Use for "will my app stay up", "what happens when a dependency fails", "reliability review", "availability review", "timeouts and retries", "double charge", "idempotent webhooks", "jobs that run twice", "dead-letter queue", "graceful shutdown", "health checks", "zero-downtime deploys", "single point of failure", "do we have SLOs", "what is our uptime".
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'for f in "${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh" "${CLAUDE_PLUGIN_ROOT}/../raystack/hooks/readonly-guard.sh" "$HOME/.claude/skills/raystack/hooks/readonly-guard.sh"; do [ -x "$f" ] && exec "$f"; done; echo "RayStack review is read-only: guard missing" >&2; exit 2'
---

# reliability-review

Find what breaks when a part fails, and what takes the whole service down. Read the code first,
then the deploy config. Report only. Never patch code and never change anything live.

## 1. Read the contract

Read `../raystack/references/review-contract.md` first and follow it for inputs, live consent,
the read-only rules, questions, the report and client data. This file only adds what is
specific to reliability and availability.

## 2. Detect the stack

Scan the repo and note the hits. Use the per-stack patterns in the checklist for the ones found.

| Files | Stack |
| --- | --- |
| `artisan`, `composer.json` with `laravel/framework` | Laravel (queues, scheduler, Horizon) |
| `manage.py`, `settings.py`, `django` or `celery` in requirements | Django, Celery |
| `Gemfile` with `rails`, `sidekiq` or `good_job` | Rails, ActiveJob |
| `package.json` with `express`, `next`, `nestjs`, `bullmq` | Node, BullMQ |
| `go.mod`, `pom.xml`, `*.csproj`, FastAPI or Flask | General items only, name the stack |
| `railway.*`, `fly.toml`, `render.yaml`, `Dockerfile*`, k8s manifests, `*.tf`, `Procfile` | Deploy config |

Also read `README`, `docs/`, runbooks, `CLAUDE.md`/`AGENTS.md` and postmortems for SLOs, backup
claims, known incidents and which dependencies are critical.

## 3. Ask for consent

Ask once, per the contract, with one batched call to the host agent's question tool:
- whether read-only live access is OK for the platform and database, and which ones,
  unless the router passed it
- whether backups exist and when a restore was last tested, if the repo does not say
- which paths make money or must never fail (checkout, signup, webhooks), if the repo does
  not say
- any uptime target or SLO, and where errors and alerts go today

If they decline, use code, config and exports only. Mark answers you could not get as
"unknown" under "Inputs used / missing" and add `(unconfirmed)` to findings that rest on them.

## 4. Work the checklist

Work through `references/checklist.md`, every item, with the stack notes that match.

- Start from the critical paths. For each one, list every dependency it calls (DB, cache,
  queue, mail, payment, search, other APIs). Then ask of each: what happens when it is slow,
  down, or returns an error? Read the client setup, the call and the error handling. Do not
  grep and guess.
- Cite file:line for every finding. Run search commands one per Bash call.
- Every finding names the failure that triggers it (for example "Stripe is slow for 60 s") and
  what the user sees (a double charge, a 502 on checkout, lost mail).
- **Availability estimate.** Add the weakest-link estimate to the executive summary. Parts in
  series multiply: one instance at 99.9% x one DB at 99.95% = about 99.85%, roughly 65 minutes
  down a month. Use the provider's published SLA, or "no SLA" when there is none. Mark it
  `(estimate)` and say what it rests on.
- Go past the checklist when the code shows a failure mode it does not list.
- Hand-offs (note briefly and point there, do not repeat their depth):
  - `infra-review`: platform config, backup setup, alert routing, CI deploy safety.
  - `scaling-review`: what breaks at 10x and 100x load, worker and pool sizing.
  - `database-review`: replication, failover, PITR and migration locking per engine.
  - `aws-bottleneck-review`: AWS limits, throttling and single-AZ checks on live AWS.
- Severity guide:
  - **Critical**: a likely failure loses or corrupts data, or takes the whole service down
    (a double charge, no backups, a single instance with no restart).
  - **High**: one dependency failing takes down a core path.
  - **Medium**: slower recovery or partial degradation.
  - **Low**: observability tidy-ups.
- Est. $/mo: write "n/a" unless the user gives a cost of downtime, or the fix adds a paid
  resource (a replica, a second instance). Then show the arithmetic.

## 5. Write the report

Write the report per the contract with skill name `reliability-review`, at
`reviews/YYYY-MM-DD-reliability-review.md`. In the executive summary, add an
**Availability estimate** line. Under "Inputs used / missing", list the stacks detected, the
critical paths traced, and every answer marked "unknown" (backups, restore test, SLO). In each
finding, add a **Fails when** line (the trigger and what users see) after **Evidence**. After
the findings, add "Reviewed, found clean" (items checked with no issue). Put restore drills,
failover tests and chaos checks for the human under "Commands for you to run".

In chat, show the top 3 findings and the report path, then offer the PDF unless the router
runs it (contract section 5).
