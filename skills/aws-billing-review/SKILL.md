---
name: aws-billing-review
description: Read-only AWS cost audit that ranks savings by $/mo. Use for "review my AWS bill", "why is AWS so expensive", "cut AWS costs", "AWS cost audit", "reduce my AWS spend", "AWS cost optimization", "what is eating my AWS budget", NAT Gateway or data transfer charges, idle or oversized EC2/RDS, Savings Plans coverage.
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'f="${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh"; [ -x "$f" ] || { echo "RayStack review is read-only: guard missing at $f" >&2; exit 2; }; exec "$f"'
---

# AWS billing review

Find where the AWS money goes and how to spend less of it. Read-only. Ends in a ranked
findings report with an estimated $/mo per finding.

## 1. Read the contract

Read `../raystack/references/review-contract.md` first and follow it for inputs, consent,
read-only rules, questions and the report. This file only adds what is specific to billing.

## 2. Detect inputs

Look in the repo for IaC:

- Terraform/OpenTofu: `*.tf`, `*.tfvars` (skip `*.tfstate*`: it holds secrets; never print secret values)
- CDK: `cdk.json`, `lib/*.ts`, `cdk.out/*.template.json`
- CloudFormation/SAM: `template.yaml`, `template.json`, `samconfig.toml`
- Serverless Framework: `serverless.yml`; Pulumi: `Pulumi.yaml`, `Pulumi.*.yaml`
- Exports already in the repo: `*.csv`, `*.parquet`, `*.csv.gz` named like costs, billing or CUR

Ask the user (one batched question) for whatever is missing:

- Cost Explorer CSV, last 3 full months, monthly, grouped by Service
- Same, grouped by Usage type (data transfer and NAT hide here)
- A Cost and Usage Report (CUR 2.0) extract, if they have one
- Which accounts and regions are in scope, and which are prod vs non-prod

## 3. Live consent

Ask once, per the contract: which AWS profile and accounts, and whether read-only live
access is OK. Billing calls need `ce:Get*`. Tell the user each Cost Explorer API call costs
$0.01, so keep the count low (one per question, not one per day or service).

## 4. Work the checklist

Work through `references/checklist.md`.

Start with the money:

1. Get the top services by cost (Cost Explorer `get-cost-and-usage` grouped by SERVICE,
   or the user's CSV). This is the first item in the checklist.
2. Rank them. Spend effort in proportion to $: a service at 40% of the bill gets deep
   checks, one under 1% gets a glance or nothing.
3. Group by USAGE_TYPE for the top 3 services, and by RECORD_TYPE to separate credits.
4. Then run the checklist sections that map to those services. Skip sections for services
   the account does not use, and say so under "Inputs used / missing".

Rules while checking:

- Every saving shows its arithmetic and the price it assumed. Prices in the checklist are
  us-east-1 on-demand list prices; say so, and scale if the region differs.
- Use real usage numbers (GB, hours, requests) from the bill or metrics, not guesses. If
  only IaC is available, mark the finding `(unconfirmed)` and give the formula.
- Recent Cost Explorer rows are `Estimated` for a day or more. Do not call a month final
  until the invoice is out.
- Never stop, resize, delete or buy anything. Purchases (Savings Plans, RIs) and schedules
  are recommendations with the exact command or IaC for the human.
- Do not double count: a rightsized instance also shrinks its Savings Plan need. Note
  overlaps in the finding.

Severity guide for billing:

- **Critical:** waste or runaway spend over 20% of the monthly bill, or unbounded growth
  (no log retention plus heavy ingest, API calls in a loop).
- **High:** a single fix worth over $100/mo or over 5% of the bill.
- **Medium:** $20 to $100/mo, or a missing guardrail (no budget, no tags, no anomaly alert).
- **Low:** under $20/mo, hygiene.

## 5. Write the report

Write the report per the contract with skill name `aws-billing-review`, at
`reviews/YYYY-MM-DD-aws-billing-review.md`. In the executive summary, put the current
monthly bill (from the bill, not estimated) next to the total est. savings.
