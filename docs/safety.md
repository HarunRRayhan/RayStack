# Safety: what reviews can and cannot do

Reviews are read-only. No review changes anything live: fixes come back as diffs or as
commands for you to run. The real boundary is the credentials you give a review. Use a
read-only cloud role and a read-only database user. The guard described here is a seatbelt
on top of that, not a sandbox.

## The guard

In Claude Code, each review turns on a hook (`skills/raystack/hooks/readonly-guard.sh`) that
checks every shell command before it runs. It needs `jq`; without it, it blocks every shell
command (fails closed). In Cursor, Codex and Grok the reviews follow the same rules, but
nothing enforces them.

**What it checks.** Only the CLIs it lists:

- `aws`, `gcloud`, `az`, `kubectl`, `oc`, `gh`, `terraform`, `tofu`, `terragrunt`, `helm`,
  `railway`, `wrangler`, `redis-cli` and the SQL clients get read verbs only, one SQL read
  per call with no SQL comments.
- Deploy tools (`pulumi`, `cdk`, `serverless`, `fly`, `vercel`, `heroku`) are blocked
  outright, as are `pg_dump` and `pg_restore`, and commands that print secret values or
  credentials (`terraform show`, `helm get values`, `aws ecr get-login-password`).
- A name counts even inside a hyphenated or slashed word (`aws-cdk`, `amazon/aws-cli`).
- Package runners (`npx`, `bunx`, `uvx`), shells (`bash`, `sh -c`, `env`), `ssh` and most
  `npm`, `yarn` and `docker` subcommands are blocked. A short list of reads such as
  `docker ps`, `docker logs --tail 200` and `npm ls` gets through.
- Dependency audits are the one package-manager exception, in forms that run no repo code:
  `npm audit`, `composer audit --no-plugins --no-scripts`, `bundle-audit check`, and
  `pip-audit` (with `-r`, also `--disable-pip` and `--no-deps` or `--require-hashes`), read
  flags only, no `fix`. They run only with your consent; without it, the review lists the
  commands for you to run.
- The six scanners (`gitleaks`, `semgrep`, `osv-scanner`, `zizmor`, `actionlint`,
  `hadolint`) run only in the read forms in
  [scanners.md](../skills/raystack/references/scanners.md). RayStack never installs them.
- Reads that return env vars or user data (Lambda configs, ECS task definitions, launch
  templates) are left for you to run.

**What it does not check.** Everything else: other tools, the agent's own file Read tool,
and scripts in the repo (a `make` target can do anything). "Reviews don't open `.env`
files or print secrets" is a rule the reviews follow, not something the guard enforces.

## The guard stays on until you start a new session

Once a review starts in Claude Code, the guard stays on for the rest of that session, also
for work that is not a review. It then also blocks, in any shell command:

- `$`, backticks, backslashes, braces, unquoted globs (`*`, `?`, `[ ]`) and redirects
  (`>`, `<`);
- anything that mentions a shell, `env`, `ssh` or `scp`;
- package runners and scripts: `npx`, `uv run`, `npm test`, `yarn`, `pnpm`, `bun` (except
  `--version`);
- container lifecycle commands (`docker compose up`, `docker run`) and docker flags before
  the subcommand;
- a monitored tool's name anywhere, so `grep -n npm Dockerfile` is blocked too.

So after a review, **start a new session before you build or run tests.** If `npm test`
is suddenly blocked, this is why.

## Read-only credentials

- **AWS:** `ReadOnlyAccess` or `ViewOnlyAccess`. No profile yet? `aws-readonly-setup` makes
  one: it signs you in with `aws login`, creates a `raystack-readonly` role with
  `ReadOnlyAccess` minus data reads (S3 objects, secrets, SSM parameters), and proves it can
  read config but not data or writes. It asks before that one IAM change and creates no
  access keys.
- **Databases** (what `database-review` recommends):
  - Postgres: a login role granted only `pg_monitor` (stats and settings, no table data).
    Every `psql` call also runs with `default_transaction_read_only=on`.
  - MySQL/MariaDB: a user with only `PROCESS` and `SELECT` on `performance_schema.*`,
    `sys.*` and `information_schema.*`.
  - Redis: an ACL user limited to `info`, `slowlog get`, `latency doctor`, `memory doctor`,
    `config get`, `dbsize` and `client list`.

  Set the connection in your own shell (`PGHOST`, `PGUSER` and so on), not in chat.
- **Other platforms** (GCP, Azure, Railway, Cloudflare, Kubernetes): a viewer or read-only
  token. With none, reviews work from your code and config and mark findings that need live
  data `(unconfirmed)`.

Every live call is asked for first, once per run. Say no and nothing outside your repo is
read.

## Privacy

- RayStack has no server and collects nothing. Your agent reads your repo and sends it to
  whatever model your agent uses, as it always does.
- Web research in the dev flow uses your agent's own search tools.
- Network calls happen only when you allow them: live reads, dependency audits,
  `/raystack update` (checks GitHub for the latest release) and the PDF export, which
  downloads `marked` through `npx`.
- Reports go to `reviews/` in your repo. They can name where secrets live (never the
  values). Decide whether to commit them or add `reviews/` to `.gitignore`.

The full rules reviews follow are in
[the review contract](../skills/raystack/references/review-contract.md).
