# Changelog

## 0.1.0 (2026-10-28)

First public release.

- Seven skills: `raystack` (the router), `aws-billing-review`, `aws-security-review`,
  `aws-bottleneck-review`, `infra-review`, `scaling-review` and `database-review`.
- A shared review contract and report template. Every review writes
  `reviews/YYYY-MM-DD-<skill>.md` with ranked findings, evidence, fixes and est. $/mo.
- A read-only guard hook that blocks mutating cloud and database commands during a review.
  It switches on automatically in Claude Code.
- `report-pdf.sh` to export a report as PDF.
- Plugin manifests for Claude Code, Cursor and Codex. Grok Build reads the Claude ones (unverified).
- `install.sh` for any agent that reads `SKILL.md` folders.
