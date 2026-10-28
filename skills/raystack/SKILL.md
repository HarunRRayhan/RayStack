---
name: raystack
description: Entry point for RayStack read-only infrastructure reviews. Use for "/raystack", "review my AWS", "review my database", "audit my stack", "which review should I run", or any request to audit cloud cost, security, bottlenecks, deploys, scaling or databases when the right review is unclear.
---

# RayStack

RayStack is a pack of read-only infrastructure reviews by Harun R. Rayhan. This skill picks
the right reviews for the repo and runs them in turn.

| Skill | Reviews |
| --- | --- |
| `aws-billing-review` | AWS spend, ranked savings in $/mo |
| `aws-security-review` | IAM, public exposure, logging, secrets on AWS |
| `aws-bottleneck-review` | AWS throttling, limits, quotas, single points on the request path |
| `infra-review` | Deploys, rollback, backups, monitoring, exposure on any platform |
| `scaling-review` | What breaks first at 10x and 100x load |
| `database-review` | Queries, indexes, migrations, backups, connections, bloat |

## Principles

Four short principle skills load on their own when a task matches; this router never runs them:
`principle-ship`, `principle-smallest-change`, `principle-ask-with-question-tool`, `principle-secrets-layout`.

## 1. Detect signals

Look at file names only. Never open `.env*` files (`.env.example`, `.env.sample` and `.env.dist`
hold names only and are fine), `*.tfstate*`, kubeconfigs or credential files.

- `*.tf`, CDK (`cdk.json`), CloudFormation templates, `serverless.yml`: the AWS reviews.
- `railway*.json`, `wrangler.toml`, `Dockerfile`, `docker-compose*`, k8s manifests,
  `fly.toml`, `app.yaml`: `infra-review`.
- `migrations/`, ORM config (Prisma, Drizzle, Django, Rails, Laravel), DB services in compose
  or IaC: `database-review`.
- Queues, workers, autoscaling config: `scaling-review`.

Then read the user's words:

- "bill", "cost", "expensive": `aws-billing-review`.
- "secure", "IAM", "public bucket": `aws-security-review`.
- "slow", "throttling", "limits": `aws-bottleneck-review`.
- "10x", "launch", "will it scale": `scaling-review`.
- AWS with no IaC: if the user mentions AWS or names an AWS profile, recommend the AWS reviews.
- No signals at all: recommend `infra-review`.

## 2. Ask once

If the user names or clearly means exactly one of the six, skip the pick. Still ask the
consent questions below if that review may make live calls.

Otherwise make ONE call to the host agent's question tool (AskUserQuestion in Claude Code).
Use plain text only when the agent has no such tool. It allows up to 4 questions with up to 4
options each, so batch:

1. "AWS reviews" (multi-select): the three `aws-*` reviews.
2. "Other reviews" (multi-select): `infra-review`, `scaling-review`, `database-review`.
3. "Live access": read-only live access yes or no, and which profile, account, project or
   region to use. Offer the options you found (e.g. profile names in `~/.aws/config`) and
   "No, IaC and exports only".
4. "Targets": only if `database-review` or `infra-review` is likely. Which database or replica
   to read (`database-review`), and the production URL (optional, for `infra-review`). Offer
   what you found and "None"; the user can type a URL in the free-text option.

- Put the recommended reviews first and add "(Recommended)" to their labels.
- Give each option a one-line reason tied to what you detected, e.g. "Found 14 `.tf` files"
  or "No AWS files found".
- If nothing is chosen, or the user declines, stop and say so. Run nothing.

## 3. Run the chosen reviews

Run each chosen review in turn, one at a time. Pass the consent answers with it:

- Claude Code: invoke the Skill tool and put the answers in the args. Invoke each review by
  the name your agent lists it under (in a Claude Code plugin install this is
  `raystack:<name>`, e.g. `raystack:aws-billing-review`; a personal install uses the bare name).
- Other agents: read `../<skill>/SKILL.md` and follow it, with the answers as instructions.

Use this wording: "live consent already given by raystack router: <answers>. The router offers
the PDF at the end." The review then skips its own consent ask (contract section 2) and its own
PDF offer, and asks only review-specific items.

When both `infra-review` and `database-review` run, database backups belong to
`database-review`. Tell `infra-review` so in its args: it cross-references the database report
and does not file a duplicate backup finding.

## 4. Wrap up

- List every report file written under `reviews/`.
- Offer the PDF once, for all the reports together, after the last review. If the user
  accepts, run `scripts/report-pdf.sh` from this skill's folder as an absolute path, once per
  report, with the report's absolute path.
