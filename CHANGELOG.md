# Changelog

## 0.3.1 (2026-10-28)

- One-command install for any agent: `npx skills add HarunRRayhan/raystack -g -a claude-code`.
- The review guard hook now falls back to `~/.claude/skills/` when `CLAUDE_PLUGIN_ROOT` is unset,
  so a global install keeps the guard working instead of blocking every shell command.

## 0.3.0 (2026-10-28)

Five content skills: write a blog post in your own voice, from topic to draft and cover. The flow
stops at a draft and a cover. It never publishes.

- `blog`: entry skill. Sets up your voice file, then runs the flow below.
- `blog-topics`: scores ideas from repo lessons, current news and your ideas file, shows the top
  10 and waits for your pick.
- `blog-draft`: writes the post as a draft in your voice, in the repo's own post format.
- `humanize`: rewrites AI-sounding prose. Adapted from Harun's own humanizer skill.
- `blog-cover`: renders a cover image from an HTML card with headless Chrome and node
  (`sips` or ImageMagick for a JPG).
- Voice file: `.raystack/voice.md` at the repo root, else `~/.raystack/voice.md`. The repo wins.
  Harun's worked example is in `skills/blog/references/voice-example.md` and is never used as
  your voice.
- `install.sh` installs and uninstalls sixteen skills. The router points blog requests at `blog`.

## 0.2.0 (2026-10-28)

Four principle skills. The agent loads them by itself when a task fits; they aren't reviews.

- `principle-ship`: done means PR, self-reviewed diff, green CI, merge, and a deploy confirmed
  live. `.raystack.json` (repo root, else `~/.raystack.json`) sets `ship.autoMerge` (default
  `false`: ask before merging) and `ship.deployCheck`.
- `principle-smallest-change`: reuse first, no speculative code, finish every caller and test,
  `shortcut: <limit>, <when to upgrade>` comments for known limits.
- `principle-ask-with-question-tool`: ask through the native question tool, at most 4 batched
  questions, recommended option first.
- `principle-secrets-layout`: `.secrets/<service>.env` with committed `.example` templates, a
  seed script, never print a value.
- `install.sh` installs and uninstalls eleven skills. The router lists the principles.
- `check-skills.sh` keeps each principle under 40 lines with an "Apply when" description.

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
  `image ls`, `version`, `info`, `system df`, `stats --no-stream`, `logs --tail N` (N at
  most 200) and `compose ps|ls|images|logs|config --services`. No flags before the subcommand, and
  no `NAME=value`, `export` or `set` in the same command. `docker inspect` and `docker image inspect` are blocked (env vars).
- Shells, `env`, `ssh`, `scp`, `sftp` and `mosh` are blocked as any word in a command, so
  `sh -c "..."` or a remote command can't hide what runs.
- `kubectl describe`/`oc describe` only for nodes, services, ingress, events and namespaces
  (workload kinds print literal env values).
- `npm` allows only `ls`, `list`, `view`, `outdated`, `audit` (no `fix`), `why`, `explain` and
  `--version`. `yarn`, `pnpm` and `bun` allow only `--version` (they run package.json scripts for
  unknown verbs).
- Cloud ops whose names look secret-ish (secret, password, token, credential, keys list,
  connection string, decrypt, ...) are blocked unless on a short metadata-only list (`kms
  list-keys`, `secretsmanager list-secrets`, `iam list-access-keys`, `gcloud secrets list`, ...).
  `--with-decryption`, `--include-value`, `--cli-input-*` and `--generate-cli-skeleton` are blocked
  by prefix, and on aws any `--` flag of 3+ characters that abbreviates them is blocked.
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
