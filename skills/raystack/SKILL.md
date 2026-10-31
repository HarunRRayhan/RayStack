---
name: raystack
description: Entry point for everything in RayStack. Use for "/raystack", "what can RayStack do", development work ("start a project", "write a PRD", "plan this", "build this", "fix this bug properly") and read-only reviews ("review my AWS", "review my database", "audit my stack", "which review should I run", cloud cost, security, bottlenecks, deploys, scaling, databases or app code security).
---

# RayStack

RayStack is Harun R. Rayhan's skill pack for building and reviewing software. This is its front
door: it works out what the user wants and runs the right skills.

| Job | Skill |
| --- | --- |
| Build: idea, PRD, spec, plan, reviewed build, ship | `dev` (it picks Quick, Standard or Full) |
| Review AWS spend, security, bottlenecks | `aws-billing-review`, `aws-security-review`, `aws-bottleneck-review` |
| Review deploys, scaling, databases, app code, speed, CI | `infra-review`, `scaling-review`, `database-review`, `app-security-review`, `performance-review`, `pipeline-security-review` |
| Scan: a set of reviews in one job (`scan <type>`) | Scan step below |
| Read-only AWS access for the reviews | `aws-readonly-setup` |
| Check a change in a real browser | `local-verify` |

Four principle skills load on their own; this router never runs them: `principle-ship`,
`principle-smallest-change`, `principle-ask-with-question-tool`, `principle-secrets-layout`.

## 0. Pick the job (in this order; the first match wins)

- The request starts with "scan" (`/raystack scan all`), or uses a scan phrase ("security scan", "performance scan", "scan and fix", "full audit", "check everything"; the last two mean `all`): Scan. "scan" elsewhere in a request ("build a barcode scan screen") is not this rule.
- Words about making or changing something ("start", "PRD", "plan", "build", "fix", "where are
  we"): hand off to `dev` and stop here, even when told to do the least possible (see `dev`).
- Other words about auditing, cost, security, speed, scaling or the database: step 1.
- Bare `/raystack`: ask once through the question tool, "Build something" (runs `dev`) or
  "Review this repo" (step 1). Recommend "Build" when `docs/plans/` or `DECISIONS.md` exists.
- An unfinished ledger in `docs/plans/`, and words not clearly a review or scan: `dev`, as above.

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

Then read the user's words:

- "bill", "cost", "expensive": `aws-billing-review`. "secure", "IAM", "public bucket":
  `aws-security-review`. "slow", "throttling", "limits": `aws-bottleneck-review`.
- "slow page", "slow endpoint", "N+1": `performance-review`. "10x", "launch", "will it scale":
  `scaling-review`.
- "security audit of my app", "IDOR", "XSS", "SQL injection": `app-security-review`.
- AWS with no IaC: if the user mentions AWS or names a profile, recommend the AWS reviews.
  No signals at all: recommend `infra-review` (not in a scan).

## 2. Ask once

If the user names or clearly means one of the nine, skip the pick, but still ask the consent
question below if that review may make live calls.

Otherwise make ONE call to the host agent's question tool (AskUserQuestion in Claude Code).
Use plain text only without such a tool. It allows up to 4 questions with up to 4 options each:

1. "AWS reviews" (multi-select): the three `aws-*` reviews.
2. "App reviews" (multi-select): `app-security-review`, `performance-review`,
   `pipeline-security-review`.
3. "Platform reviews" (multi-select): `infra-review`, `scaling-review`, `database-review`.
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
  fix"). If the PDF is accepted, run `scripts/report-pdf.sh` from this skill's folder (absolute
  path) once per report, with the report's absolute path.

## Scan

`scan <type>` (security, performance, scalability, infra, aws, database, all) runs steps 1, 3 and 4 on
the type's review list. Type and consent: [references/scans.md](references/scans.md), which replaces
step 2 (no review pick) with one question-tool call. It also has the table, skipped reviews and the
combined `reviews/YYYY-MM-DD-scan-<type>.md` (skill `scan-<type>`).
