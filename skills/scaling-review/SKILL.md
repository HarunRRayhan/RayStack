---
name: scaling-review
description: Read-only scaling review that finds what breaks first at 10x and 100x load across app code, queues, caches, databases and infra (AWS, GCP, Azure, Railway, Cloudflare, VPS/Docker) and ends in a ranked findings report. Use for "will this scale", "what breaks at 10x traffic", "what breaks at 100x", "prepare for a launch spike", "we are about to go viral", "scaling review", "capacity planning", "load readiness", "can we handle Black Friday", "is our architecture ready to grow".
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'f="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/skills/raystack/hooks/readonly-guard.sh"; [ -x "$f" ] || { echo "RayStack review is read-only: guard missing at $f" >&2; exit 2; }; exec "$f"'
---

# Scaling review

Find the first thing that breaks at 10x and at 100x today's load, and what each fix costs.
Read-only. Every fix is a code or IaC diff, or a command for the human to run.

## 1. Read the contract

Read `../raystack/references/review-contract.md` first and follow it for inputs, live consent,
read-only rules, questions, the report and the footer. Do not restate it here.

## 2. Live consent

Per contract section 2: ask once, before the first live call, which account, project, platform
or database to read. Declined means IaC, code and exports only.

## 3. Measure today's load, then set the target

- Pull measured peaks before asking the user anything: checklist item 0 ("Today's headroom"),
  14-day maximum and p99 for CPU, requests, response time, queue age, DB CPU and connections,
  Redis stats. Also read exported dashboards, APM or log exports, load-test results,
  autoscaling config and runbooks.
- Ask only for what is still unknown, in ONE batched question (question tool per contract):
  - requests per minute, average and peak
  - peak concurrent users or connections
  - data size: largest tables, object storage, cache memory
  - growth: expected traffic over the next 3 to 12 months, and any launch date or spike event
  - background work: jobs per minute and the longest job duration
- Targets are always 10x and 100x of the peak, not the average. If the user gives a launch
  spike, add it as a third target.
- If nothing is measured or known, mark the load as assumed in the report and state the
  assumption.

## 4. Walk the system

Use `references/checklist.md`. Walk in this order:

1. **Edge**: CDN, WAF, rate limits, cache hit ratio, origin exposure.
2. **Request path**: load balancer, web/app processes, per-request code (N+1, sync external
   calls, in-process state, local disk).
3. **Shared state**: sessions, cache, locks, uploads, counters.
4. **Data**: connections and pooling, hot queries, write contention. For engine depth (indexes,
   `EXPLAIN`, vacuum, unsafe migrations) point to `database-review`.
5. **Background work**: queues, workers, schedulers, retries, webhooks, third-party API limits.
6. **Platform limits**: autoscaling bounds, plan or quota ceilings, single replicas. For AWS
   service quotas and per-service limits point to `aws-bottleneck-review`.

For each component, name:

- what it is and where it is defined (file:line or live command)
- the first thing that breaks at 10x, and at 100x
- the symptom users or operators see (timeouts, 5xx, queue lag, OOM, 429s, lost sessions)
- the fix, and its cost at 10x

Do the arithmetic. Use the capacity formulas in the checklist (connections, workers,
throughput). Never invent a number: if an input is missing, show the formula with the missing
term and list it under "Inputs used / missing".

Do not recommend new infrastructure (Kafka, a dedicated queue cluster, sharding, microservices)
until the numbers show the current piece breaks inside the target. Prefer the cheapest fix that
moves the break point past 100x.

## 5. Report

Write the report per contract with skill name `scaling-review`:
`reviews/YYYY-MM-DD-scaling-review.md`.

Add a **Breaks first** section right after "Inputs used / missing", sorted by the load at which
each component breaks, lowest first:

```markdown
## Breaks first

Today: <peak req/min, concurrency, data size>. Targets: 10x = <...>, 100x = <...>.

| Component | Breaks at | Symptom | Fix | Est. cost at 10x |
|---|---|---|---|---|
| <component> | <~3x / 10x / 100x, with the math> | <what users see> | <fix> | <$/mo with arithmetic, or n/a> |
```

- "Breaks at" is a multiple of today's peak, backed by a formula or a measured limit. Mark
  guesses `(unconfirmed)`.
- Every row with a real risk inside 100x also appears as a finding. Severity: breaks before
  10x = Critical or High; between 10x and 100x = Medium; beyond 100x = Low or omit.
- Each finding's **Est. $/mo** is the added monthly cost of the fix at 10x, or the cost of the
  outage it prevents, with the arithmetic.
- Never generate load. A load-test plan (checklist item 15) goes in "Commands for you to run",
  against a disposable environment only, never production.
