# Scans

`/raystack scan <type>` runs a set of reviews as one job. `*` marks a review that runs only
when its signals are found (router step 1). Run the reviews in this order.

| Type | Reviews, in run order |
| --- | --- |
| security | `app-security-review`, `pipeline-security-review*`, `aws-security-review*`, `infra-review*` |
| performance | `performance-review`, `database-review*`, `aws-bottleneck-review*` |
| scalability | `scaling-review`, `database-review*` |
| infra | `infra-review`, `pipeline-security-review*`, `aws-security-review*`, `aws-bottleneck-review*` |
| aws | `aws-billing-review`, `aws-security-review`, `aws-bottleneck-review` |
| database | `database-review` |
| all | `app-security-review*`, `pipeline-security-review*`, `performance-review*`, `database-review*`, `scaling-review*`, `infra-review*`, `aws-security-review*`, `aws-bottleneck-review*`, `aws-billing-review*` |

For `all`, every review is conditional: those with no signals are listed as skipped.
Scaling signals: queues, workers, schedulers, autoscaling or replica-count config (step 1).
Pipeline signals: CI workflows, a `Dockerfile`, IaC or a lockfile (a lockfile alone runs the
supply-chain items).

## Type and consent

Skip step 2's review pick. Make ONE question-tool call with only what the mapped reviews need
(drop a question no mapped review uses):

1. "Scan type", only when the type is missing or unknown: `all` (Recommended), security,
   performance, and "Other" for the rest (scalability, infra, aws, database). When this is
   asked, size questions 2 to 4 for the reviews `all` would run here.
2. "Live access" as in step 2 item 4 (at most 4 options). Only offer AWS setup when AWS signals
   are found.
3. "Network scanners" (multi-select): dependency audits + osv-scanner, semgrep, `gh api` with
   the OWNER/REPO and branch from `git remote` and the default branch. In a scan this is the
   only place app-security-review's dependency audits are asked.
4. "Targets": what was found (e.g. a `DATABASE_URL`-style name from `.env.example`, DB or app
   hosts from config), at most 3, plus "None"; others typed in "Other". Nothing found: drop it.

Pass the answers to every review with the router step 3 wording, which says
"part of a raystack scan". A declined or empty answer means that review works from files
only for it; the scan still runs. The reviews ask nothing more: each assumes the safe default
(worst case for security, "unknown" for numbers), lists each assumption under
"Inputs used / missing", and marks findings that depend on one `(unconfirmed)` (contract
section 2).

## Skipped reviews

A mapped review with no signals is skipped, not run. Record each skip with its reason, e.g.
"aws-security-review: no AWS files or profile found". If only one review runs, put the skips in
the chat reply; no combined summary is written.

## Combined summary

When 2 or more reviews ran, write `reviews/YYYY-MM-DD-scan-<type>.md` after the last review.
Follow `report-template.md` with skill `scan-<type>`:

1. Executive summary: overall state, top 3 risks across all reports.
2. "Reviews run / skipped" table: review, status (run or skipped), report path or the reason.
3. Findings: every finding from every report, ranked by the contract rule (Critical > High >
   Medium > Low; ties by est. $/mo). Each title ends with `see <report>`; keep the evidence
   and fix to a line or two, the full text stays in the report. A review's own one-line
   `see <report>` cross-references are not findings: leave them out.
4. Duplicates (same file:line or same resource) become one merged entry that names both
   reports. Keep the higher severity.

The summary is a report like the others: list it in the wrap-up and include it in the PDF offer.
