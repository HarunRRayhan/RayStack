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
- Container CLIs (`docker`, `podman`, `nerdctl`, compose) are a read allow-list: `ps`, `images`,
  `image ls|inspect`, `version`, `info`, `system df`, `stats --no-stream`, `logs --tail N` (N at
  most 200) and `compose ps|ls|images|logs|config --services`. No flags before the subcommand, and
  no `NAME=value`, `export` or `set` in the same command. `docker inspect` is blocked (env vars).
- Shells and `env` are blocked as any word in a command, so `sh -c "..."` can't hide a command.
- `npm` allows only `ls`, `list`, `view`, `outdated`, `audit` (no `fix`), `why`, `explain` and
  `--version`. `yarn`, `pnpm` and `bun` allow only `--version` (they run package.json scripts for
  unknown verbs).
- Cloud ops whose names look secret-ish (secret, password, token, credential, keys list,
  connection string, decrypt, ...) are blocked unless on a short metadata-only list (`kms
  list-keys`, `secretsmanager list-secrets`, `iam list-access-keys`, `gcloud secrets list`, ...).
  `--with-decryption`, `--include-value`, `--cli-input-*` and `--generate-cli-skeleton` are blocked
  by prefix, so abbreviations count.
- Reads that return env vars, user data or passwords are blocked outright: `ssm get-parameter*`,
  Lambda function configs and lists, `ecs describe-task-definition`, launch template data and
  versions, `glue get-connection(s)`, `cognito-idp describe-user-pool-client` and userData
  attributes. Checklist steps that used them are now commands for you to run.
- `kubectl get` takes only allow-listed flags, and `-o` only `json`, `yaml`, `wide`, `name`,
  `jsonpath=` or `custom-columns=`. No `-f`, `-k`, `-R`, `-w` or `--raw`.
- `helm`: `list`, `history` and `status` only in table form, `status` only with `--hide-notes`,
  `get metadata` only, and no `template`.
- The review contract notes that logs can hold secrets and must be redacted before quoting.

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
