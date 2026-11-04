---
name: audit
description: Entry point for RayStack's read-only reviews and scans. Use for "/audit", "/audit all", "/audit security", "audit my stack", "review my codebase", "which review should I run", "review my AWS", "review my database", cloud cost, security, bottlenecks, deploys, scaling, databases, app code security, performance, N+1 queries, CI/CD or GitHub Actions security, architecture, CQRS, MVC, frontend, reliability, availability, code quality or tech debt, and scans that run several reviews as one job ("scan", "scan all", "scan security").
---

# Audit

The entry point for reviews, as `dev` is for building. It picks the reviews that fit this
repo, asks once for consent, runs them one at a time and gathers the reports. Every review is
read-only.

| Type | What runs |
| --- | --- |
| `/audit` | Detects what the repo has and recommends reviews (steps below) |
| `/audit <area>` (security, database, frontend, architecture, AWS cost...) | That review, step 2 skips the pick |
| `/audit all` or `/audit <scan type>` | A scan: a set of reviews as one job (Scan below) |

The thirteen reviews: `aws-billing-review`, `aws-security-review`, `aws-bottleneck-review`,
`infra-review`, `scaling-review`, `database-review`, `app-security-review`,
`performance-review`, `pipeline-security-review`, `architecture-review`, `frontend-review`,
`reliability-review`, `codebase-review`. Read-only AWS access: `aws-readonly-setup`.

## 0. Scan or review

- `all`, `scan`, or a scan phrase ("security scan", "full audit", "check everything", "scan and fix"; the last three mean `all`): Scan below.
  "scan" inside an unrelated request ("build a barcode scan screen") is not a scan.
- A request to build or fix something: hand off to `dev` and stop.
- Anything else: step 1.

## 1. Detect signals

File names only. Never open `.env*` files (`.env.example`, `.env.sample`, `.env.dist` hold
names only and are fine), `*.tfstate*`, kubeconfigs or credential files.

- `*.tf`, CDK (`cdk.json`), CloudFormation templates, `serverless.yml`: the AWS reviews.
- `railway*.json`, `wrangler.toml`, `Dockerfile`, `docker-compose*`, k8s manifests,
  `fly.toml`, `app.yaml`: `infra-review`.
- `migrations/`, ORM config (Prisma, Drizzle, Django, Rails, Laravel), DB services in compose
  or IaC: `database-review`. Queues, workers, autoscaling config: `scaling-review`.
- App code (routes, controllers, an ORM): `app-security-review`; with an ORM or a frontend
  build also `performance-review`.
- CI workflows, a `Dockerfile`, IaC or k8s: `pipeline-security-review`.
- App code: also `architecture-review` and `codebase-review`. A frontend build (React, Vue,
  Svelte, Angular, Next, Nuxt, Inertia): `frontend-review`. App code with outbound calls,
  queues, jobs or deploy config: `reliability-review`.

Then read the user's words:

- "bill", "cost", "expensive": `aws-billing-review`. "secure", "IAM", "public bucket":
  `aws-security-review`. "slow", "throttling", "limits": `aws-bottleneck-review`.
- "slow page", "slow endpoint", "N+1": `performance-review`. "10x", "launch", "will it scale":
  `scaling-review`.
- "security audit of my app", "IDOR", "XSS", "SQL injection": `app-security-review`.
- "architecture", "CQRS", "MVC", "layers", "god class", "coupling": `architecture-review`.
  "frontend", "React", "Vue", "accessibility", "re-renders": `frontend-review`. "reliability",
  "availability", "uptime", "SLO", "retries", "failover": `reliability-review`. "code quality",
  "tech debt", "codebase", "dead code", "test coverage": `codebase-review`. "database",
  "indexes", "slow queries": `database-review`. "CI", "pipeline": `pipeline-security-review`. "infra", "deploys": `infra-review`. "security" with no AWS: `app-security-review`.
- AWS with no IaC: if the user mentions AWS or names a profile, recommend the AWS reviews.
  No signals at all: recommend `infra-review` (not in a scan).

## 2. Ask once

If the user names or clearly means one of the thirteen reviews, skip the pick, but still ask the consent
question below if that review may make live calls.

Otherwise make ONE call to the host agent's question tool (AskUserQuestion in Claude Code).
Use plain text only without such a tool. It allows up to 4 questions with up to 4 options each:

1. "AWS and CI reviews" (multi-select): the three `aws-*` reviews, `pipeline-security-review`.
2. "Code reviews" (multi-select): `app-security-review`, `performance-review`,
   `architecture-review`, `codebase-review`, `frontend-review`.
3. "Platform reviews" (multi-select): `infra-review`, `scaling-review`, `database-review`,
   `reliability-review`.

   Over 4 in a group: drop reviews with no signals; still over, name the cut one for "Other".
4. "Live access": read-only yes or no, and which profile, account, project or region. Outside a
   scan it also covers `app-security-review`'s audits (in a scan, scans.md question 3 asks instead).
   Offer at most 2 found profiles (e.g. `~/.aws/config`; others in "Other"), "No, IaC and exports
   only" and, with no working read-only AWS profile, "Set up read-only access" (run `aws-readonly-setup` first).

- Put recommended reviews first, labelled "(Recommended)", each with a one-line reason tied to
  what you detected, e.g. "Found 14 `.tf` files". Nothing chosen, or declined: stop, run nothing.

## 3. Run the chosen reviews

Run each chosen review in turn, one at a time, passing the consent answers:

- Claude Code: invoke the Skill tool with the answers in the args, by the name your agent lists
  (a plugin install uses `raystack:<name>`, e.g. `raystack:aws-billing-review`; a personal
  install the bare name).
- Other agents: read `../<skill>/SKILL.md` and follow it, with the answers as instructions.

Use this wording: "consent already given by raystack router for <what was asked, e.g. live
access, scanners, targets>: <answers>. The router offers the PDF at the end." In a scan, add
"This is part of a raystack scan." The review skips only the questions answered here and its
PDF offer, and in a scan asks nothing (contract section 2). From the second review on, add the
reports already written: "a finding already filed there gets a one-line `see <report>`
reference, not a second entry". Run `database-review` before `infra-review`.

## 4. Wrap up

- List every report file written under `reviews/`. Then offer the PDF once, for all the reports;
  after a scan, offer `dev` to fix the findings in the same question (recommended for "scan and
  fix"). If the PDF is accepted, run `../raystack/scripts/report-pdf.sh` (absolute
  path) once per report, with the report's absolute path.

## Scan

`scan <type>` (security, performance, scalability, reliability, architecture, code, frontend,
infra, aws, database, all) runs steps 1, 3 and 4 on
the type's review list. Type and consent: [scans.md](../raystack/references/scans.md), which replaces
step 2 (no review pick) with one question-tool call. It also has the table, skipped reviews and the
combined `reviews/YYYY-MM-DD-scan-<type>.md` (skill `scan-<type>`).
