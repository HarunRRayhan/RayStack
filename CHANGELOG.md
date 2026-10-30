# Changelog

## 0.6.4 (2026-10-30)

- `/raystack` and `dev`: once you ask for the flow, its steps run even when another plugin,
  hook or instruction says to do the least possible. Those rules still shape the code, and
  subagents are told the same. Only you can drop a step.
- Quick track: the review must be a fresh reviewer subagent whenever the host has a subagent
  tool. Reviewing inline is now only for hosts without one.

## 0.6.3 (2026-10-30)

- `dev-build`: with no git remote, the ledger now ends with `Committed: <commit> on <branch>
  (no remote, not merged)` instead of `Shipped:`. `Shipped:` now always means merged. Session
  resume treats either line as finished. Found in a live Standard-track trial.

## 0.6.2 (2026-10-29)

- `install.sh` now removes skills that earlier versions installed but RayStack no longer ships
  (the old blog skills), on install and on `--uninstall`. It only removes folders it installed
  itself (marker or link into the checkout); same-named folders of your own are left alone.

## 0.6.1 (2026-10-29)

- Quick track: the separate review is now mandatory, even for a one-line fix. The behaviour
  note can live in the reply for tiny fixes. With no git remote, ship stops at the commit.

## 0.6.0 (2026-10-29)

- Removed the blog writing skills: `blog`, `blog-topics`, `blog-draft`, `humanize` and
  `blog-cover`. RayStack now focuses on development and read-only reviews.
- `/raystack` is now the entry point for everything: it hands build work to `dev`, runs the
  review flow for audits, and asks which one when the request is unclear.
- `install.sh` installs and uninstalls twenty-one skills. It leaves the old blog skills in place;
  remove them by hand: `rm -rf ~/.claude/skills/{blog,blog-topics,blog-draft,humanize,blog-cover}`
  (use your agent's skills folder).

## 0.5.0 (2026-10-29)

- New development flow, seven skills: `dev` (entry point), `dev-hub`, `dev-research`, `dev-prd`,
  `dev-spec`, `dev-plan` and `dev-build`. Three tracks by size: Quick (a bug or small change),
  Standard (one slice) and Full (a new product). Decisions go in `DECISIONS.md` and are never
  asked twice. The build uses a fresh implementer and reviewer per task, a ledger so a stopped
  run resumes, and a final review.
- The `raystack` router hands development requests to `dev`.
- `principle-ship` also checks that the docs still match the code.
- `install.sh` installs and uninstalls twenty-six skills.

## 0.4.1 (2026-10-29)

- New `aws-readonly-setup`: when no read-only AWS profile works, the agent signs you in with
  `aws login`, creates a `raystack-readonly` role with `ReadOnlyAccess` plus an inline deny on data reads
  (S3 objects, secrets, SSM parameters, table rows, function code), adds the profile and proves
  it can read config but not data or writes. One IAM change, asked first, no access keys. The
  router offers it, and the review contract points every AWS review to it.
- `install.sh` installs and uninstalls nineteen skills.

## 0.4.0 (2026-10-28)

- New `app-security-review`: the seventh read-only review. It reads app code for authorization, injection, secrets and session bugs. It never sends requests to a running app. Dependency audits run only with your live consent.
- New `local-verify`: a playbook for checking a user-facing change in a real local browser. `principle-ship` calls it. It never edits `.env`, never touches production or shared databases, and says so when no browser tool is available.
- The review guard allows dependency audits, only in forms that run no repo code: `npm audit`, `composer audit`, `pip-audit` and `bundle-audit check`. Each must be the bare command name, not a path.
- The guard watches only the CLIs it lists, so `python -m pip_audit` is not covered. That is an accepted residual.
- `install.sh` installs and uninstalls eighteen skills.

## 0.3.3 (2026-10-28)

From the first real run (five reviews on a Terraform repo):

- A review run by the router no longer mentions the PDF; the router offers it once at the end.
- The router passes earlier reports to each later review, so a finding already filed gets a
  one-line `see <report>` reference instead of a duplicate entry. `database-review` runs before
  `infra-review`.

## 0.3.2 (2026-10-28)

- Fix: in Claude Code, reviews from an installed skill (`npx skills add`, `install.sh`, or a
  project's `.claude/skills/`) blocked every shell command. Claude Code points
  `CLAUDE_PLUGIN_ROOT` at the skill's own folder, so the hook now finds the guard in the sibling
  `raystack` skill. Confirmed live in Claude Code for a project install and a plugin install.
- `install.sh` no longer rewrites the hook, and `--link` installs now keep the guard working.

## 0.3.1 (2026-10-28)

- One-command install for any agent: `npx skills add HarunRRayhan/RayStack -g -a claude-code`.
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
