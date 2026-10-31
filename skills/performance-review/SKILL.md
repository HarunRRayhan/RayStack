---
name: performance-review
description: Read-only per-request performance review of the application code with a ranked findings report. Use for "why is this page slow", "N+1 queries", "slow endpoint", "too many queries", "slow API", "page load is slow", "bundle size", "response time", "memory spike", "request timeout", or a Laravel, Django, Rails, Node (Prisma, TypeORM, Sequelize, Drizzle) or frontend build performance review.
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'for f in "${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh" "${CLAUDE_PLUGIN_ROOT}/../raystack/hooks/readonly-guard.sh" "$HOME/.claude/skills/raystack/hooks/readonly-guard.sh"; do [ -x "$f" ] && exec "$f"; done; echo "RayStack review is read-only: guard missing" >&2; exit 2'
---

# performance-review

Find what one request costs today: queries, milliseconds and bytes. Report only. Never patch
code and never change anything live. For behaviour at 10x load use `scaling-review`.

## 1. Read the contract

Read `../raystack/references/review-contract.md` first and follow it for inputs, live consent,
the read-only rules, questions, the report and client data. This file only adds what is
specific to per-request performance.

## 2. Detect the stack

Scan the repo and note the hits. Use the per-ORM patterns in the checklist for the ones found.

| Files | Stack |
| --- | --- |
| `artisan`, `composer.json` with `laravel/framework` | Laravel, Eloquent |
| `manage.py`, `settings.py`, `django` in requirements | Django ORM |
| `Gemfile` with `rails`, `app/models/` | Rails, ActiveRecord |
| `package.json` with `prisma`, `typeorm`, `sequelize` or `drizzle-orm` | Node ORM |
| `vite.config.*`, `webpack.config.*`, `next.config.*`, `package.json` | Frontend build |
| Other (Flask, FastAPI, Spring, Go, .NET) | General items only, name the stack |

Also read `README`, `docs/`, `CLAUDE.md`/`AGENTS.md` for the hot routes and known slow pages.

## 3. Ask for consent

Ask once, per the contract, with one batched call to the host agent's question tool:
- whether the database may be read for query statistics (`pg_stat_statements`,
  `performance_schema`), and which database
- whether APM or log exports exist to read, and where
- which pages or endpoints feel slow, if the repo does not say

If they decline, use code, config and exports only. List the read commands under "Commands
for you to run". If `pg_stat_statements` is not enabled, say so in "Inputs used / missing".

## 4. Work the checklist

Work through `references/checklist.md`, every item, with the ORM and build notes that match.

- Start from the hot paths: home, list pages, search, the API routes with the most traffic.
  Open the route, controller, query and template, and trace one request to the response.
  Do not grep and guess.
- Cite file:line for every finding. Run search commands one per Bash call.
- **Cost per request.** Every finding states the cost with arithmetic: queries per request
  (for example 50 rows x 3 relations + 1 = 151 queries), added milliseconds (queries x
  measured or typical ms), or bytes (rows x bytes per row). Mark any number that is not
  measured `(estimate)` and say what it rests on. Measured numbers come from consented
  statistics, exports or built asset sizes.
- Rank by how often the path runs times what it costs. A slow admin page ranks below a
  slightly slow home page.
- Go past the checklist when the code shows a cost it does not list.
- Hand-offs: index choice, `EXPLAIN` and engine depth go to `database-review`. Behaviour at
  10x and 100x load goes to `scaling-review`. Latency from AWS services (Lambda cold starts,
  API Gateway, RDS limits) goes to `aws-bottleneck-review`. Note it briefly and point there.
- Severity guide:
  - **Critical**: an endpoint already timing out or running out of memory.
  - **High**: per-request queries or latency that grow with data size on a hot path.
  - **Medium**: a fixed but avoidable cost on a hot path.
  - **Low**: cold paths.
- Est. $/mo: write "n/a" unless the user gives a cost, or the fix removes a paid resource.

## 5. Write the report

Write the report per the contract with skill name `performance-review`, at
`reviews/YYYY-MM-DD-performance-review.md`. Under "Inputs used / missing", list the stacks
detected, whether statistics were read and which numbers are estimates. In each finding, add
a **Cost per request** line (the arithmetic) after **Evidence**. After the findings, add
"Reviewed, found clean" (items checked with no issue). Put read commands the user must run
and any lazy-load detection switch to try under "Commands for you to run".

In chat, show the top 3 findings and the report path, then offer the PDF unless the router
runs it (contract section 5).
