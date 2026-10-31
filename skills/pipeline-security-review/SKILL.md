---
name: pipeline-security-review
description: Read-only CI/CD and supply-chain security review with a ranked findings report. Use for "is my CI secure", "GitHub Actions security", "pull_request_target", "pin actions to SHA", "workflow permissions", "secrets in CI", "Dockerfile security", "container runs as root", "Terraform or Kubernetes misconfig", "dependency confusion", "lockfiles", "Dependabot or Renovate", "branch protection", or a GitLab CI review.
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'for f in "${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh" "${CLAUDE_PLUGIN_ROOT}/../raystack/hooks/readonly-guard.sh" "$HOME/.claude/skills/raystack/hooks/readonly-guard.sh"; do [ -x "$f" ] && exec "$f"; done; echo "RayStack review is read-only: guard missing" >&2; exit 2'
---

# pipeline-security-review

Find the ways an outsider gets code into your build or deploy: CI workflows, container
builds, IaC and Kubernetes manifests, and the dependency supply chain. Report only. Never
edit a workflow, never re-run a job and never change a repo or cloud setting.

This review covers build and deploy, not the running cloud account. It never triggers a
workflow, opens a PR or pushes; each finding gives the attack path for the user to check.

## 1. Read the contract

Read `../raystack/references/review-contract.md` first and follow it for inputs, live consent,
the read-only rules, questions, the report and client data. This file only adds what is
specific to pipeline security.

## 2. Detect what is there

Scan the repo and work every checklist area that has files.

| Files | Checklist area |
| --- | --- |
| `.github/workflows/*.yml`, `.github/actions/`, `action.yml` | CI: GitHub Actions |
| `.gitlab-ci.yml` and its `include:` files | CI: GitLab CI (same items) |
| `Dockerfile*`, `Containerfile`, `.dockerignore` | Containers |
| `*.tf`, CloudFormation, CDK, Pulumi, Kubernetes YAML, `Chart.yaml` | IaC and Kubernetes |
| Lockfiles, `package.json`, `.npmrc`, `requirements*.txt`, `pyproject.toml`, `composer.json` | Supply chain |
| `.github/dependabot.yml`, `renovate.json`, `CODEOWNERS` | Supply chain |

Also read `README`, `docs/`, `SECURITY.md`, `CLAUDE.md`/`AGENTS.md`: who may push, which jobs deploy.

## 3. Ask for consent

osv-scanner sends the lockfile's package list to osv.dev, and `gh api` reads the repo's
settings on GitHub, so they are live calls. Ask once, per the contract, with one batched call
to the host agent's question tool:
- whether osv-scanner may run on the lockfiles, unless the router passed it
- whether `gh api` may read visibility, the workflow token default, branch protection and rules, and for which repo and branch, unless the router passed it
- whether the repo is public and whether fork PRs get secrets, if `gh api` is declined

If they decline, list those commands under "Commands for you to run".

## 4. Run the scanners

Use the forms in `../raystack/references/scanners.md` exactly. Never install a scanner.
- zizmor and actionlint on `.github/workflows` and hadolint on each Dockerfile, when
  installed. They are local and need no consent.
- osv-scanner on the lockfiles, when installed and consented.
- Missing ("command not found"): say so under "Inputs used / missing", put the install line
  from the scanners file under "Commands for you to run" and check by reading.
- Confirm each hit by reading the file. An unconfirmed hit goes under "Worth hardening".
- checkov and trivy are never run (D-006). When IaC or Dockerfiles are found, write these
  under "Commands for you to run", for a checkout the user trusts (checkov can load Python
  checks from the repo's `.checkov.yaml`, and trivy reads `trivy.yaml` from the folder):
  - `brew install checkov trivy`
  - `checkov -d . --compact --quiet`
  - `trivy config .`
  - `trivy fs --scanners vuln,secret,misconfig .`
  - `trivy image IMAGE:TAG` for each image the repo builds

`gh api`: only after consent, run only the `gh api` reads in checklist items 4, 6 and 18
(`gh api repos/OWNER/REPO/branches/BRANCH/protection` and the rest); if one is denied, or
still 403 after the item's fallback, list it under "Commands for you to run".

## 5. Work the checklist

Work through `references/checklist.md`, every area that has files.

- Open each workflow, Dockerfile and manifest and read the whole job or stage. Do not grep
  and guess.
- Cite file:line for every finding. Run search commands one per Bash call; grep for monitored
  tool names with a bracket class, per the contract.
- **Finding bar.** A finding needs a concrete attack path: who (anyone who can open a fork PR,
  issue or comment; a compromised action, image or package maintainer; one contributor with
  write access), what they send or push, and what they gain (secrets, a write token, a cloud
  role, a release or deploy). Without one, it goes under a "Worth hardening" section after
  the findings, never ranked as a finding.
- Go past the checklist when the files show a risk it does not list.
- Hand-offs. Note it briefly and point there:
  - the AWS account and IAM, including the live OIDC role: `aws-security-review`
  - the runtime deploy setup (hosting, backups, rollback, origin exposure, the running
    cluster): `infra-review`
  - application code (an RCE that a root container makes worse): `app-security-review`
- Severity guide:
  - **Critical**: anyone on the internet runs code with secrets or a write token (a pwn
    request, script injection from an issue or PR title), or can assume a cloud role (OIDC
    trust with a wildcard `sub`).
  - **High**: a compromised third-party action, image or package gets deploy secrets
    (unpinned action in a secret-holding job, `curl | sh` in a deploy job), a self-hosted
    runner on a public repo, a secret baked into a pushed image.
  - **Medium**: one contributor can ship to production unreviewed (no branch protection), a
    broad token in a job with a narrow way in, dependency confusion on a private scope, no
    frozen install in a publishing job.
  - **Low**: issues that need an existing admin or maintainer compromise.
- Est. $/mo: write "n/a" unless the user gives a cost of the incident.

## 6. Write the report

Write the report per the contract with skill name `pipeline-security-review`, at
`reviews/YYYY-MM-DD-pipeline-security-review.md`. Under "Inputs used / missing", list the
areas found, the scanners run or missing, and whether branch protection was read. In each
finding, add an **Attack path** line (who, what they send or push, what they gain) after
**Evidence**. After the findings, add "Worth hardening" (unranked) and "Reviewed, found
clean" (the items checked with no issue). Put checkov, trivy, missing installs and any
denied `gh api` read under "Commands for you to run".

In chat, show the top 3 findings and the report path, then offer the PDF unless the router
runs it (contract section 5).
