---
name: infra-review
description: Read-only infrastructure review with a ranked findings report. Use for "review my infrastructure", "infra audit", "is my deploy setup safe", "check my backups and rollback", "single points of failure", "is my origin exposed behind the CDN", or a Railway, Cloudflare, VPS, Docker, Kubernetes, AWS, GCP or Azure deploy review.
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'for f in "${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh" "${CLAUDE_PLUGIN_ROOT}/../raystack/hooks/readonly-guard.sh" "$HOME/.claude/skills/raystack/hooks/readonly-guard.sh"; do [ -x "$f" ] && exec "$f"; done; echo "RayStack review is read-only: guard missing" >&2; exit 2'
---

# infra-review

Review how the app is deployed, rolled back, backed up, watched and exposed. Never change
anything live.

## 1. Read the contract

Read `../raystack/references/review-contract.md` first and follow it for inputs, live consent,
the read-only rules, questions, the report and client data. This file only adds what is
specific to infrastructure.

## 2. Detect the platforms

Scan the repo and map each hit to a checklist section. Review only the sections that match,
plus General.

| Files | Section |
| --- | --- |
| `*.tf`, `cdk.json`, `template.yaml`, `serverless.yml`, `samconfig.toml`, `buildspec.yml`, `appspec.yml`, `.aws/` | AWS |
| `app.yaml`, `cloudbuild.yaml`, `service.yaml` (Cloud Run), `*.tf` with `google` provider | GCP |
| `*.bicep`, `azuredeploy.json`, `azure-pipelines.yml`, `.azure/`, `*.tf` with `azurerm` provider | Azure |
| `railway.json`, `railway.toml`, `nixpacks.toml` | Railway |
| `wrangler.toml`, `wrangler.json`, `wrangler.jsonc`, `_headers`, `_redirects`, `purge` calls in workflows | Cloudflare |
| `Dockerfile*`, `docker-compose*.yml`, `compose*.yml`, `Caddyfile`, `nginx*.conf`, `traefik*`, systemd units, `deploy.sh` | VPS/Docker |
| `fly.toml`, `render.yaml`, `vercel.json`, `netlify.toml`, `Procfile` | General only, note the platform |
| k8s manifests (`kind: Deployment`), `Chart.yaml`, `kustomization.yaml` | VPS/Docker (Kubernetes item) and the cloud that hosts it |
| `.github/workflows/*.yml`, `.gitlab-ci.yml` | General: CI pipeline safety |

Also read `README`, `docs/`, runbooks and any `CLAUDE.md`/`AGENTS.md` for deploy notes, backup
claims and known incidents. Check code for CDN-only headers (`Cf-Ipcountry`,
`Cf-Connecting-Ip`, `X-Forwarded-For`) since they decide how serious origin exposure is.

If nothing matches, say so in the report, list the files you looked for, and ask the user which
platform runs production.

## 3. Ask for consent

Ask once, per the contract, in one batched question, each item unless the router passed it:
- which platforms and accounts, projects, subscriptions or Railway projects to read
- whether read-only live access is OK (`aws`, `gcloud`, `az`, `railway`, `wrangler`, `kubectl`)
- the production URL, if not in the repo (for `curl -sI` header checks)

If they decline, review from repo files only and mark live-only findings `(unconfirmed)`.

## 4. Work the checklist

Work through `references/checklist.md`: General first, then each detected platform section.

- Run each evidence command as written, one CLI call per Bash call. Replace UPPERCASE
  placeholders with the user's own values. If the guard blocks one, rewrite it once per the
  contract, otherwise move it to "Commands for you to run".
- Cite file:line for repo evidence and a short output excerpt for commands.
- Go past the checklist when the repo shows a risk it does not list.
- AWS depth belongs to the sibling skills. Note the finding briefly and point the user to
  `aws-billing-review` (cost), `aws-security-review` (IAM, exposure, encryption) or
  `aws-bottleneck-review` (limits, throughput). Do not duplicate their checks here.
- Severity guide:
  - **Critical**: data loss or full outage is one event away (no backups, origin open with
    trusted CDN headers, secrets in the repo, data on ephemeral disk).
  - **High**: no tested rollback, untested restore, no alerting, single host or zone for
    production, singleton jobs that double-run.
  - **Medium**: slow or fragile deploys, missing CI guards, cache or purge mistakes.
  - **Low**: hygiene, naming, cost tidy-ups.
- Est. $/mo: use the checklist prices as a starting point, adjust for the user's region and
  size, and show the arithmetic. Write "n/a" for pure risk findings.

## 5. Write the report

Write the report per the contract with skill name `infra-review`, at
`reviews/YYYY-MM-DD-infra-review.md`. Under "Inputs used / missing", list the platforms detected
and the sections reviewed. Put every write the user must do (dashboard changes, domain removal,
`wrangler secret put`, `beta` CLI reads) under "Commands for you to run".

In chat, show the top 3 findings and the report path, then offer the PDF unless the router runs it (contract section 5).
