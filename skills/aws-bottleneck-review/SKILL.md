---
name: aws-bottleneck-review
description: Read-only AWS performance and limits review that finds the narrowest bottleneck on the request path and ranks fixes. Use for "why is my AWS app slow", "find AWS bottlenecks", "Lambda throttling", "Lambda cold starts or timeouts", "RDS connections maxed out", "SQS backlog growing", "API Gateway 429 or 504", "ALB 5xx", "EBS IOPS limit", "T3 CPU credits", "hitting AWS limits", "service quotas", "is this single-AZ".
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'f="${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh"; [ -x "$f" ] || { echo "RayStack review is read-only: guard missing at $f" >&2; exit 2; }; exec "$f"'
---

# AWS bottleneck review

Find what limits throughput, latency or availability on an AWS workload. Read-only. End with a
ranked findings report.

## 1. Read the contract

Read `../raystack/references/review-contract.md` first and follow it for inputs, consent,
read-only rules, questions and the report. It wins over anything below.

## 2. Detect inputs

Look in the repo before asking anything:

- IaC: Terraform (`*.tf`), CDK (`cdk.json`, `lib/*.ts`), CloudFormation/SAM (`template.y*ml`),
  Serverless (`serverless.y*ml`), Pulumi, ECS task definitions, Dockerfiles, nginx configs.
- Exports: CloudWatch metric snapshots (CSV/JSON), load test results (k6, Locust, JMeter,
  Artillery), APM traces (X-Ray, Datadog, New Relic, OpenTelemetry), Lambda REPORT log lines.
- Symptoms the user already gave: error codes (429, 502, 503, 504), timeouts, slow endpoints.

Note what is present and what is missing. The report lists both.

## 3. Live consent

Ask once, per the contract, through the question tool: which AWS profile and region(s), and is
read-only live access OK. Batch in the same ask: the slow or failing endpoint, when it happens
(time window, peak hour), and the latency or throughput target if one exists. If declined, work
from IaC and exports only.

## 4. Map the request path, then find the narrowest limit

1. Draw the path for the slow or failing flow: edge (CloudFront, WAF) -> load balancer or API
   Gateway -> compute (Lambda, ECS/Fargate, EC2/ASG) -> queue (SQS, SNS, EventBridge) ->
   data (RDS/Aurora, DynamoDB, ElastiCache, S3) -> egress (NAT, third-party APIs).
2. For each hop write its hard limit (timeout, concurrency, connections, IOPS, quota) and its
   observed peak. The hop with the least headroom is the bottleneck. A fix downstream of it is
   wasted until it moves.
3. Check timeouts line up: each hop's timeout must be shorter than the caller's, and retries
   must not multiply load on the hop that is already saturated.

## 5. Work through the checklist

Work through `references/checklist.md` layer by layer. Skip layers the workload does not use
and say so in the report.

Metrics rules:

- Use CloudWatch `get-metric-statistics` or `get-metric-data` over a stated window. Default to
  the last 14 days, period 3600, statistic `Maximum` or extended statistic `p99`. Averages hide
  saturation; never judge a limit from `Average` alone.
- Fill the `YYYY-MM-DDT00:00:00Z` placeholders with literal dates. Never use `$(date ...)`;
  the guard denies `$`.
- Replace UPPERCASE placeholders (`FUNCTION_NAME`, `DB_ID`, `QUEUE_URL`) with real values.
- Every finding names the window, statistic and sample size. One short sample or a green
  health route proves neither a p95 target nor availability.
- Load test numbers from a busy laptop or a single local process prove nothing about hosted
  throughput. Ask for a run against a staging stack, or mark the finding `(unconfirmed)`.
- Measure before recommending a split or a bigger instance. Often two serial calls run in
  parallel fix the p95 for free.

If the guard blocks a read command, rewrite it once per the contract. Anything that writes, or
needs a support plan or tool you lack, goes under "Commands for you to run".

## 6. Write the report

Write it per the contract with skill name `aws-bottleneck-review`, at
`reviews/YYYY-MM-DD-aws-bottleneck-review.md`.

- Executive summary starts with the request path and the single narrowest limit on it.
- Severity guide:
  - Critical: a limit already hit in the window (throttles, 5xx, maxed connections,
    exhausted credits or burst balance), or a single-AZ data store with no restore path.
  - High: peak above 80% of a hard limit, or a timeout/retry mismatch that can loop or
    redeliver.
  - Medium: headroom under 2x for expected growth, missing alarms on a limit.
  - Low: tuning with small latency gains.
- Est. $/mo: the cost of the fix (RDS Proxy, Multi-AZ, gp3 IOPS, provisioned concurrency) or
  the waste it removes (retries, surplus credits, NAT data). Show the arithmetic with the
  region's on-demand price. Write "n/a" when the input is missing.
- Each fix is an IaC diff or a command for the human to run. Quota increases are requests the
  human files (`aws service-quotas request-service-quota-increase` is a write).
