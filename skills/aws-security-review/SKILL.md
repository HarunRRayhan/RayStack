---
name: aws-security-review
description: Read-only AWS security review with a ranked findings report. Use for "AWS security review", "is my AWS account secure", "audit IAM", "check for public S3 buckets", "are my security groups open", "is root MFA on", "do I have secrets in env vars or user data", "is CloudTrail/GuardDuty on", "can my origin be reached around CloudFront", or a pre-launch AWS security audit.
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'f="${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh"; [ -x "$f" ] || { echo "RayStack review is read-only: guard missing at $f" >&2; exit 2; }; exec "$f"'
---

# AWS security review

Find the ways an AWS account can be breached, rank them, and hand back fixes. Never change
anything live.

## 1. Read the contract

Read `../raystack/references/review-contract.md` first and follow it. It covers inputs, live
consent, the read-only rules, questions, the report format and the footer. This file adds only
what is specific to AWS security.

## 2. Detect inputs

Look in the repo for:

- Terraform (`*.tf`, `*.tfvars`, backend config), CDK, CloudFormation/SAM (`template.yaml`),
  Serverless, Pulumi.
- `.github/workflows/` and other CI config (OIDC trust, stored AWS keys).
- `user_data`, cloud-init, Dockerfiles, ECS task definitions.
- Committed `.env*` files and `*.tfstate*`: list them by name only
  (`git ls-files | grep -iE 'tfstate|[.]env'`, or `grep -l`). Never open or cat them. Report
  the file path and that it is present; that alone is the finding.

Exports to ask for when live access is missing or declined:

- IAM credential report CSV (IAM console, Credential report, or the human runs
  `aws iam generate-credential-report` then downloads it).
- Security Hub findings export, or Trusted Advisor security checks export.
- `aws iam get-account-authorization-details --output json` saved to a file.

## 3. Live consent

Ask once, per the contract: AWS profile, account, which regions are in use, and whether
read-only calls are OK. Recommend `SecurityAudit` or `ViewOnlyAccess` credentials. Note that
`ReadOnlyAccess` can read data (S3 objects, SSM values, Lambda env vars), so prefer
`SecurityAudit` for this review.

## 4. Work through the checklist

Go through `references/checklist.md` section by section. For regional services, repeat the
checks in every region in use, not only the default one.

- Record each item as a finding, a pass, or inconclusive. A check you could not run is
  inconclusive, never a pass. An empty scanner or CLI result only means "nothing found by
  this check".
- Prefer IaC evidence (file:line) when both exist, and confirm with a live call when allowed.
- When IaC and live state disagree, report the drift as its own finding.

## 5. Secrets

- Never print a secret value in chat, the report, or a command you run. Query names and flags
  only (`keys(Environment.Variables)`, `list-secrets`, `describe-parameters`).
- Grep for secret patterns in the location-only form from the checklist (`| cut -d: -f1,2`),
  and run gitleaks only with `--redact`. Never run `terraform plan` yourself; ask the human.
- If a secret shows up anyway, cite its location only: file:line, or resource plus field, with
  the value masked (`AKIA************WXYZ`, `postgres://user:****@host`).
- Treat any secret found in git, user data, plain env vars, a bucket, or logs as exposed. The
  fix is rotate first, then remove.

## 6. Severity

Rank by how directly an outsider gets in, internet exposure and credential compromise first.

- **Critical:** a working path from the internet or a leaked credential to data or admin.
  Examples: public bucket or snapshot with real data; DB or admin port open to `0.0.0.0/0`;
  root access keys present; live AWS keys in the repo, user data or a public place; a role
  assumable by another account with no ExternalId and wide rights; IMDSv1 on a public host
  that fetches user-supplied URLs.
- **High:** a step away from compromise, or no way to notice one. Examples: root without MFA;
  `Action: "*"` on a workload role; IAM user keys older than 90 days; CloudTrail off; GitHub
  OIDC `sub` wildcard; origin reachable around the CDN/WAF; secrets in plain env vars.
- **Medium:** weak defense in depth. Examples: GuardDuty or Config off in a used region;
  unencrypted volumes or caches; no KMS rotation; no flow logs; IMDSv1 on internal hosts.
- **Low:** hygiene. Examples: user-attached policies, unrestricted egress, missing security
  contact, no alerts on root sign-in.

Raise one level when the resource is production or holds customer data; lower one level when
it is clearly a sandbox with nothing sensitive. Est. $/mo is usually "n/a"; state the risk in
words instead, and give the monthly cost of the fix where the checklist lists one.

## 7. Write the report

Write the report per the contract and the raystack report template, with skill name
`aws-security-review`, to `reviews/YYYY-MM-DD-aws-security-review.md`. Put every write the
human must do (enabling services, deleting keys, removing public access, decoding user data)
under "Commands for you to run".
