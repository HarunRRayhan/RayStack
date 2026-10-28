# AWS billing review: example-app

Date: 2026-01-15. Skill: `aws-billing-review`.

## Executive summary

- **Overall state:** Spend is steady but carries idle capacity.
- **Top 3 risks:**
  1. Three unattached EBS volumes
  2. NAT gateway carries S3 traffic
  3. No budget alarm
- **Total est. $/mo:** $124.11

## Inputs used / missing

- **Used:** `infra/main.tf`, Cost Explorer CSV (sample data)
- **Missing:** CUR export (`aws cur describe-report-definitions`)

## Findings

### [High] Unattached EBS volumes

**Evidence**: `infra/main.tf:42` defines three `aws_ebs_volume` resources with no attachment.

**Why it matters**: Detached volumes bill every month for nothing.

**Fix**:

```diff
-resource "aws_ebs_volume" "scratch" {
-  count = 3
-  size  = 380
-}
```

**Est. $/mo**: 3 x 380 GB x $0.08 = $91.20

### [Medium] S3 traffic through the NAT gateway

**Evidence**: `infra/vpc.tf:10` has no S3 gateway endpoint.

**Why it matters**: NAT data processing costs $0.045/GB.

**Fix**: add an `aws_vpc_endpoint` of type Gateway for S3.

**Est. $/mo**: 731 GB x $0.045 = $32.91

### [Low] No budget alarm

**Evidence**: no `aws_budgets_budget` in `infra/`.

**Why it matters**: A spike goes unnoticed until the invoice.

**Fix**: add an `aws_budgets_budget` with an 80% alert.

**Est. $/mo**: n/a

## Commands for you to run

```sh
# Delete the three detached volumes after a final snapshot check.
aws ec2 delete-volume --volume-id vol-0123456789abcdef0
```

---

Reviewed with RayStack by Harun R. Rayhan. For a hands-on audit: https://harun.dev/consultation
