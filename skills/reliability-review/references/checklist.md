# Reliability checklist

Each item: **Check**, **Evidence** (Grep = code search with the agent's search tool; Run =
read-only command that passes the guard, only after consent), **Fails because**, **Fix**.
Placeholders are UPPERCASE. Replace them with literal values before running.

Run each `Run:` command once, never in a loop. Prefer a read replica when one exists. Never
test a failure on a live system: failover drills and restore tests go under "Commands for you
to run", on a disposable environment.

## 1. Outbound calls with no timeout

- **Check**: every HTTP, DB, cache and queue client sets a connect and a read timeout.
- **Evidence**: Grep client setup and calls: `Http::`, `Guzzle`, `requests\.(get|post)`,
  `httpx`, `axios`, `fetch\(`, `Net::HTTP`, `Faraday`, SDK clients (`Stripe`, `S3Client`,
  `OpenAI`). Look for `timeout`, `connect_timeout`, `AbortSignal.timeout`, `read_timeout`,
  DB `connect_timeout`/`statement_timeout`, Redis `timeout`/`read_timeout`. Many clients
  default to no timeout (`requests`, `fetch`) or to minutes.
- **Fails because**: one hung dependency holds a worker until the platform kills it. With 8
  workers and a stalled API, 8 requests stop the whole app, including pages that never call it.
- **Fix**: connect 1 to 3 s, read 5 to 10 s, a total deadline below the platform request
  timeout. Set it once on a shared client, not per call.

## 2. Retries without backoff, or on unsafe operations

- **Check**: retries are capped, use exponential backoff with jitter, honour `Retry-After`,
  and wrap only idempotent calls (GET, or a write sent with an idempotency key).
- **Evidence**: Grep `retry`, `retries`, `backoff`, `tries`, `Retry-After`, `p-retry`,
  `tenacity`, `retryable`, `->retry\(`. Read what each retry wraps: a POST that creates a
  charge, an order or a message.
- **Fails because**: retrying a non-idempotent write after a timeout repeats it (the first try
  may have succeeded). Retries with no jitter hit a recovering service in lockstep and keep it
  down.
- **Fix**: retry only timeouts, 408, 429 and 5xx, at most 3 times, with backoff such as
  `base x 2^n` plus random jitter. Send an idempotency key on every retried write.

## 3. No circuit breaker or fallback for non-critical dependencies

- **Check**: calls to recommendations, analytics, geo, search, avatars or other optional
  services are wrapped so a failure is skipped, not raised.
- **Evidence**: Grep for `circuit`, `breaker`, `opossum`, `pybreaker`, `resilience4j`,
  `Polly`, `stoplight`; read the `try`/`catch` around optional calls on core pages.
- **Fails because**: a slow optional widget makes every page that shows it slow or a 500.
- **Fix**: short timeout, catch, log, render without it. Add a breaker that skips the call for
  30 to 60 s after repeated failures, so a dead service costs nothing per request.

## 4. Payment, order and webhook handlers do not dedupe

- **Check**: handlers that charge, create orders, grant access or process provider webhooks
  dedupe by a key (provider event ID, idempotency key, order reference).
- **Evidence**: Grep webhook routes and handlers (`webhook`, `stripe`, `paddle`, `paypal`,
  `event.id`, `Idempotency-Key`, `idempotency_key`). Look for a unique index on the event or
  key column in migrations, or a `firstOrCreate`/`INSERT ... ON CONFLICT DO NOTHING` guard.
- **Fails because**: providers deliver webhooks at least once and retry on any non-2xx or
  timeout. Users double-click. Without a dedupe key the second delivery charges, ships or
  emails twice.
- **Fix**: store the event ID under a unique constraint and skip duplicates in the same
  transaction as the side effect. Pass an idempotency key to the provider on charges. Verify
  the signature first, return 2xx fast, and do the work in a job.

## 5. Jobs that are not safe to run twice

- **Check**: every queued job gives the same result when it runs twice.
- **Evidence**: Grep job classes (`implements ShouldQueue`, `@shared_task`, `perform`,
  `Worker(`, `queue.process`). Read jobs that send mail, charge, increment counters or call
  APIs. Look for `ShouldBeUnique`, `WithoutOverlapping`, `unique_for`, a "done" flag or status
  check before the side effect.
- **Fails because**: queues deliver at least once. A worker killed after the side effect and
  before the ack runs the job again.
- **Fix**: check-then-act on a status column inside a transaction, a unique key per job, or
  an upsert instead of an increment.

## 6. Retries uncapped, no dead-letter queue, poison messages

- **Check**: job retries are capped, failures land in a dead-letter queue or failed-jobs table,
  someone is alerted when it grows, and one bad message cannot block the queue.
- **Evidence**: Grep `--tries`, `tries`, `max_retries`, `attempts`, `maxReceiveCount`,
  `redrive_policy`, `deadLetter`, `failed_jobs`, `failed()`, `on_failure`, `removeOnFail`.
  - Run: `PGOPTIONS=-cdefault_transaction_read_only=on psql -X -c "select n_live_tup from pg_stat_user_tables where relname = 'failed_jobs'"`
  - Run: `AWS_PROFILE=PROFILE aws sqs get-queue-attributes --queue-url QUEUE_URL --attribute-names RedrivePolicy ApproximateNumberOfMessages`
- **Fails because**: uncapped retries loop forever and burn workers. With no DLQ, failed work
  vanishes. A DLQ nobody reads is the same as none. A poison message that crashes the worker
  stops every message behind it.
- **Fix**: cap tries (3 to 5) with backoff, route failures to a DLQ or `failed_jobs`, alert
  when its count rises, and add a `failed()` handler that records why.

## 7. Visibility timeout shorter than the job, and overlapping schedules

- **Check**: the queue's retry or visibility timeout is longer than the longest job timeout,
  and scheduled tasks cannot overlap or run on more than one instance.
- **Evidence**: Grep `retry_after` (Laravel `config/queue.php`), `VisibilityTimeout`,
  `visibility_timeout` (Celery), `lockDuration` (BullMQ), job `timeout`. For schedules:
  `withoutOverlapping`, `onOneServer`, `pg_advisory_lock`, `redlock`, cron in every web
  replica (`schedule:run` in the web start command).
- **Fails because**: a job longer than the visibility timeout is handed to a second worker
  while the first still runs, so it runs twice. A cron that takes longer than its interval
  stacks up, and a scheduler on N replicas runs every task N times.
- **Fix**: visibility timeout = longest job timeout + margin. One scheduler with a lock that
  outlives the task. Throughput sizing goes to `scaling-review`.

## 8. Multi-step writes outside a transaction

- **Check**: writes that must all succeed or all fail run in one transaction.
- **Evidence**: Grep controllers and services that do two or more `save`/`create`/`update`/
  `insert` calls in a row (order plus line items, debit plus credit, user plus profile). Look
  for `DB::transaction`, `transaction.atomic`, `ActiveRecord::Base.transaction`,
  `prisma.$transaction`, `BEGIN`.
- **Fails because**: a crash or error between steps leaves half-written data (an order with no
  items, money debited and not credited) that no code path repairs.
- **Fix**: wrap the steps in one transaction. Keep external calls (HTTP, mail) out of it.

## 9. "Write to the DB, then publish" with no outbox

- **Check**: code that commits a row and then sends a message, event, email or webhook.
- **Evidence**: Grep for `dispatch`, `publish`, `emit`, `send`, `Mail::` right after a save or
  commit; `afterCommit`, `on_commit`, `transaction.on_commit`, an `outbox` table.
- **Fails because**: if the process dies between the commit and the publish, the event is lost.
  If it publishes inside the transaction and then rolls back, consumers act on data that does
  not exist.
- **Fix**: write the event to an outbox table in the same transaction and relay it with a
  worker, or at least dispatch after commit (`afterCommit`, `on_commit`).

## 10. Backups missing or restore never tested

- **Check**: automated backups exist, live off the primary host, and a restore was tested.
- **Evidence**: backup or PITR settings in IaC (`backup_retention_period`, `point_in_time`),
  platform backup config, backup jobs, a dated restore note in `docs/`. If none of this is in
  the repo, ask; if there is no answer, mark it "unknown".
- **Fails because**: a dropped table, bad migration or lost disk with no backup is permanent.
  An untested backup often fails on the day it is needed.
- **Fix**: automated daily backups plus PITR, a copy in another account or region, and a
  quarterly restore into a scratch environment with the date written down. Backup setup depth
  goes to `infra-review` and `database-review`.

## 11. No graceful degradation when a dependency is down

- **Check**: what each core path does when the cache, search, mail, object storage or a third
  party is down.
- **Evidence**: read the cache client calls (`Cache::`, `redis`, `cache.get`) for a fallback
  to the DB on error; search calls for a fallback or a friendly error; mail sent in the request
  instead of a queue; uploads that fail the whole form when storage is down.
- **Fails because**: a cache outage that raises instead of missing turns a speed-up into a
  hard dependency. Mail sent inline fails signups when the mail provider is down.
- **Fix**: treat cache errors as misses, queue mail and webhooks, show a degraded result
  (no search, cached prices) instead of a 500, and feature-flag optional parts.

## 12. Health checks that lie or cascade

- **Check**: a liveness check (process is up) and a readiness check (can serve traffic) exist
  and are used by the platform.
- **Evidence**: Grep health routes (`/health`, `/up`, `/healthz`, `/ready`), and the platform
  config (`healthcheckPath`, `livenessProbe`, `readinessProbe`, `HEALTHCHECK`).
- **Fails because**: a liveness check that calls the DB or a third party restarts every
  instance when that dependency blips, turning a partial outage into a full one. A static
  `200` reports up while the app cannot reach its DB.
- **Fix**: liveness returns 200 with no downstream calls. Readiness checks the DB and cache
  with short timeouts. The platform gates deploys and traffic on readiness.

## 13. No graceful shutdown

- **Check**: on SIGTERM the web server stops taking requests and finishes in-flight ones, and
  workers finish or release the current job.
- **Evidence**: Grep `SIGTERM`, `process.on\('SIGTERM'`, `server.close`, `graceful`,
  `--max-time`, `stop_grace_period`, `terminationGracePeriodSeconds`, `drainingSeconds`,
  `STOPSIGNAL`. Check the start command: a shell wrapper (`sh -c`) often does not pass the
  signal on.
- **Fails because**: every deploy cuts in-flight requests (users see 502s) and kills jobs
  mid-run, which then retry or are lost.
- **Fix**: handle SIGTERM, stop accepting, drain, then exit. Grace period above the longest
  request and job. Use `exec` in start scripts so the app gets the signal.

## 14. Single points of failure

- **Check**: one web instance, one zone, one DB with no replica or failover, a cache or queue
  that everything needs on one node.
- **Evidence**: replica counts (`numReplicas`, `replicas:`, `desired_count`, `min_size`),
  `multi_az`, DB replica or HA settings, one Redis with no persistence. Restart policy
  (`restartPolicyType`, `restart: always`).
- **Fails because**: the service is only as available as its weakest single part, and a
  single instance with no restart policy stays down until a human notices.
- **Fix**: at least two web instances behind the load balancer, a restart policy, an HA or
  failover DB where the uptime target needs it. State the cost of each step and the
  availability estimate before and after.

## 15. Deploys with downtime or no rollback path

- **Check**: deploys are rolling or blue/green and gated on readiness; there is a known way to
  roll back to the last good build.
- **Evidence**: deploy strategy in platform config (`maxUnavailable`, `overlapSeconds`,
  `deployment_configuration`), images tagged by commit, a rollback section in the runbook.
- **Fails because**: stop-then-start deploys drop traffic every release. Without a tagged last
  good build, rollback means a rebuild during the incident.
- **Fix**: rolling deploys with readiness gates, commit-tagged images, a written rollback
  command. Pipeline depth goes to `infra-review`.

## 16. Migrations that lock tables

- **Check**: migrations on large tables that add a column with a default, add an index without
  `CONCURRENTLY`, change a column type, or add a foreign key that scans the table.
- **Evidence**: read recent migrations; check table sizes with consent.
  - Run: `PGOPTIONS=-cdefault_transaction_read_only=on psql -X -c 'select relname, n_live_tup from pg_stat_user_tables order by n_live_tup desc limit 10'`
- **Fails because**: a table lock during deploy blocks every read or write on that table for
  the length of the migration, and the app times out.
- **Fix**: `CREATE INDEX CONCURRENTLY`, add nullable then backfill in batches, expand and
  contract across releases, `lock_timeout` on migrations. Engine depth goes to
  `database-review`.

## 17. Errors do not reach a tracker

- **Check**: unhandled exceptions, job failures and frontend errors go to an error tracker.
- **Evidence**: Grep `sentry`, `bugsnag`, `rollbar`, `honeybadger`, `newrelic`, `datadog`,
  `opentelemetry`; the exception handler and job failure hooks; empty `catch` blocks that
  swallow errors.
- **Fails because**: failures nobody sees are found by customers, days later.
- **Fix**: add the tracker to web, workers and the frontend, with release tags. Log and
  re-raise in catch blocks that cannot recover.

## 18. No alerts, SLOs or runbooks

- **Check**: alerts on error rate, latency, queue age and failed jobs; an uptime target or SLO;
  a runbook per common failure.
- **Evidence**: alert rules in IaC or config, an external uptime probe, `docs/runbooks`,
  `SLO` in docs. If none, ask for the uptime target.
- **Fails because**: with no alert the outage lasts until someone complains. With no target,
  nobody can say whether a fix is worth its cost.
- **Fix**: an external probe on the readiness route, alerts on 5xx rate and p95 latency, a
  written target (for example 99.9%, about 43 minutes a month), and a one-page runbook per
  dependency. Alert routing depth goes to `infra-review`.

## 19. No rate limiting on public endpoints

- **Check**: login, signup, password or magic-link, search, contact forms and public APIs have
  rate limits.
- **Evidence**: Grep `throttle`, `RateLimiter`, `express-rate-limit`, `rack-attack`,
  `django-ratelimit`, `slowapi`, edge rules in CDN or WAF config.
- **Fails because**: one client or bot can use every worker and take the service down for
  everyone else.
- **Fix**: per-IP and per-user limits on these routes, stricter on auth, with a 429 and
  `Retry-After`. Edge limits for floods.

## 20. Unbounded queues and pools

- **Check**: in-memory queues, worker pools, connection pools and concurrency have a maximum.
- **Evidence**: Grep `pool`, `max_connections`, `connection_limit`, `pool_size`,
  `concurrency`, `Promise.all` over unbounded lists, in-process arrays used as queues.
- **Fails because**: an unbounded buffer grows until the process runs out of memory, and an
  unbounded pool exhausts DB connections, so one burst takes down every instance.
- **Fix**: set a max on every pool and queue, reject or shed load when full, and limit
  concurrency (`p-limit`, a semaphore). Pool sizing at load goes to `scaling-review`.

## 21. Missing config fails at first request, not at boot

- **Check**: required env vars are validated when the app starts.
- **Evidence**: Grep config reads (`env\(`, `process.env.`, `os.environ.get`, `ENV.fetch`,
  `os.Getenv`) with no default and no check; look for a boot-time schema (`zod`, `envalid`,
  `pydantic` settings, `ENV.fetch` without a default, a Laravel boot check). Read
  `.env.example` for names only.
- **Fails because**: a missing key deploys green, passes health checks, then fails on the
  first payment or email, maybe hours later.
- **Fix**: validate required variables at boot and exit with the missing name, so the deploy
  fails its readiness gate and the old version keeps serving.
