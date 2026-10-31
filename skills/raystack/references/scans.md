# Scans

`/raystack scan <type>` runs a set of reviews as one job. `*` marks a review that runs only
when its signals are found (router step 1). Run the reviews in this order.

| Type | Reviews, in run order |
| --- | --- |
| security | `app-security-review`, `pipeline-security-review`, `aws-security-review*`, `infra-review*` |
| performance | `performance-review`, `database-review*`, `aws-bottleneck-review*` |
| scalability | `scaling-review`, `database-review*` |
| infra | `infra-review`, `pipeline-security-review`, `aws-security-review*`, `aws-bottleneck-review*` |
| aws | `aws-billing-review`, `aws-security-review`, `aws-bottleneck-review` |
| database | `database-review` |
| all | every review whose signals are found, `database-review` before `infra-review` |

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
   and fix to a line or two, the full text stays in the report.
4. Duplicates (same file:line or same resource) become one merged entry that names both
   reports. Keep the higher severity.

The summary is a report like the others: list it in the wrap-up and include it in the PDF offer.
