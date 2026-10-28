# Changelog

## 0.1.1 (2026-10-28)

Read-only guard fixes.

- SQL statements with comments are blocked (`--`, and `#` for MySQL, MariaDB, mycli and usql).
  A comment could hide the gap between a function name and `(`.
- CLI names now match inside hyphenated or slashed words (`npx aws-cdk deploy`,
  `docker run amazon/aws-cli ...`). Package runners (`npx`, `bunx`, `uvx`, `pnpm dlx`,
  `yarn dlx`, `npm exec`, `pipx run`) and `docker run`/`podman run` are blocked during a review.
- `kubectl get --raw` is blocked, and secret paths after `/` or `,` are caught.
- `terraform show` and `terraform state show` are blocked (they print attribute values).
  `state list` still works.
- Commands that print credentials are blocked: AWS token and password reads (`ecr get-login-password`,
  `sts get-session-token`, `ec2 get-password-data` and more), `az ... keys list`, and
  `helm get values|all|manifest`.
- More tools are blocked outright: `vc`, `ntl`, `cdktf`, `sst`, `amplify`, `copilot`, `dropuser`,
  `createuser`, `pg_dump`, `pg_dumpall` and `pg_restore`.
- `docker --context x compose config` and other global flags before `compose` no longer skip the
  compose secret check.

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
