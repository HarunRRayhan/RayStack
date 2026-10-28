---
name: database-review
description: Read-only database review for PostgreSQL, MySQL/MariaDB, Redis, DynamoDB, RDS/Aurora and SQLite. Use for "review my database", "slow queries", "missing indexes", "unused indexes", "Postgres review", "MySQL review", "Redis review", "DynamoDB review", "is this migration safe", "RDS/Aurora backups", "connection pool exhausted", "table bloat", "database costs too much".
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'f="${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh"; [ -x "$f" ] || { echo "RayStack review is read-only: guard missing at $f" >&2; exit 2; }; exec "$f"'
---

# Database review

Find what will hurt this database: slow or unindexed queries, unsafe migrations, missing
backups, connection exhaustion, bloat, wasted spend. Read-only. The output is a ranked
findings report.

## 1. Read the contract

Read `../raystack/references/review-contract.md` first and follow it. It covers inputs,
live consent, the read-only rules, questions, the report format and the no-client-data
rule. This file only adds what is specific to databases.

## 2. Detect engines

Scan the repo before asking anything. Review only the sections of the checklist that match.

| Engine | Signals |
|---|---|
| PostgreSQL | `postgres` image in compose, `DB_CONNECTION=pgsql`, `postgres://` URLs, `pg`/`psycopg`/`sqlx`/`asyncpg` deps, `engine = "postgres"` or `aurora-postgresql` in IaC |
| MySQL/MariaDB | `mysql`/`mariadb` image, `DB_CONNECTION=mysql`, `mysql2`/`pymysql` deps, `engine = "mysql"` or `aurora-mysql` |
| Redis | `redis`/`valkey` image, `REDIS_URL`, `CACHE_STORE=redis`, `aws_elasticache_*`, `AWS::ElastiCache::*` |
| DynamoDB | `aws_dynamodb_table`, `AWS::DynamoDB::Table`, `dynamodb.Table` (CDK), `client-dynamodb`, boto3 `dynamodb` |
| RDS/Aurora | `aws_db_instance`, `aws_rds_cluster`, `AWS::RDS::*`, `rds.DatabaseInstance`/`DatabaseCluster` (CDK) |
| SQLite | `DB_CONNECTION=sqlite`, `*.sqlite`/`*.db` files, `sqlite3` deps |
| Migrations | `database/migrations`, `db/migrate`, `migrations/`, `prisma/migrations`, `alembic/versions`, `drizzle/` |

One grep finds most of them:

`grep -rliE 'postgres|mysq|mariad|redis|valkey|dynamodb|aws_db_instance|aws_rds_cluster|elasticache|sqlite' --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git .`

Also note:
- which services connect to the DB and how (web, workers, scheduler, Lambda), and the
  pool size each one uses
- which DB CI tests against (SQLite in CI while production runs Postgres is a finding)
- whether any service runs migrations on boot

## 3. Live consent

Ask once, per the contract, in one batched question:
- which databases to inspect (connection env or host, database name) and which AWS profile
  and region for RDS/Aurora, DynamoDB and ElastiCache
- whether a read replica or staging copy exists. Prefer it over the primary
- whether read-only live access is OK at all

Never connect to a production database without the user's explicit yes to that database.
Recommend, before any call:
- PostgreSQL: a login role granted only `pg_monitor` (stats and settings, no table data),
  and prefix every psql call with `PGOPTIONS=-cdefault_transaction_read_only=on`
- MySQL/MariaDB: a user with only `PROCESS` and `SELECT` on `performance_schema.*`,
  `sys.*` and `information_schema.*`
- Redis: an ACL user with an explicit allow-list, no data reads:
  `-@all +info +slowlog|get +latency|doctor +memory|doctor +config|get +dbsize +client|list`
- AWS: `ReadOnlyAccess` or `ViewOnlyAccess`

Command shapes that pass the guard:
- `PGOPTIONS=-cdefault_transaction_read_only=on psql -X -c "select ..."`
- `mysql -e "select ..."` or `mysql -e "show ..."`
- `redis-cli INFO memory`
- `sqlite3 -readonly app.db "pragma integrity_check"`

Rules for SQL: one statement per command, wrap it in double quotes, use single quotes for
literals, no `$`, no backslashes, no `;`, no `/*` comments. Only functions on the guard's
read-only list work (`count`, `sum`, `round`, `substring`, `age`, `now`, `pg_size_pretty`,
`pg_relation_size`, ...). If a query needs another function, rewrite it or put it in
"Commands for you to run". `explain analyze` runs the query: use it only on a replica or
staging, only for reads, and only after consent. Plain `explain` needs `SELECT` on the table,
which the monitoring role lacks: ask the user to run it, or to grant `SELECT` on those tables.

An empty result or an error (view missing, feature off, no privilege) means "unavailable",
never "no problems". Say so under "Inputs used / missing" and use the item's fallback.

If live access is declined, review IaC, migrations and code, and list the exact queries
from the checklist under "Commands for you to run".

## 4. Work through the checklist

Open `references/checklist.md`. For each detected engine, take every item:
1. Collect the evidence: the grep over migrations/IaC/code, and the live query if allowed.
2. Decide if it is a finding. Judge "big table" from real row counts and sizes, not names.
3. Write the finding with evidence, why it matters, the fix as a diff or a command for the
   human, and Est. $/mo with arithmetic.

Migration review works fully offline. Read every pending or recent migration and flag:
- ALTERs that take a long exclusive lock or rewrite the table
- index builds that are not `CONCURRENTLY` (Postgres) or not online (MySQL)
- backfills in the same transaction as the schema change
- `NOT NULL` without a default on a big table
- destructive changes (drop, rename, truncate) without an expand/contract plan and a
  stated rollback path

Severity guide:
- **Critical**: data loss or outage is likely (no backups, wraparound near, a migration that
  locks a hot table, a production DB reachable from the internet)
- **High**: an outage under normal growth (pool exhaustion, a missing index on a hot path,
  replication slot filling the disk)
- **Medium**: slow paths, bloat, waste over $50/mo
- **Low**: hygiene

## 5. Write the report

Write the report per the contract with skill name `database-review`, at
`reviews/YYYY-MM-DD-database-review.md`. Name each database and engine version you
inspected under "Inputs used". Put every write the user must run (index builds, `VACUUM`,
`ALTER`, config changes, `redis-cli --bigkeys`) in "Commands for you to run".
