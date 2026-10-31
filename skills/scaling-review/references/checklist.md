# Scaling checklist

Each item: **Check**, **Evidence** (Grep = code/IaC search with the agent's search tool; Run =
read-only command that passes the guard), **Breaks because**, **Fix**, **Cost curve**.
Placeholders are UPPERCASE (`SERVICE`, `REGION`, `CLUSTER`, `START_ISO`). Replace them with
literal values before running (no `$(date ...)`: the guard denies it).

Production safety:

- Run each `Run:` command once. Never in a loop, under `watch`, or in parallel.
- DB queries go to a read replica when one exists. Prefer catalog estimates
  (`pg_stat_user_tables.n_live_tup`, `pg_class.reltuples`) over `count(*)` on big tables.
- `curl`: one HEAD or GET per URL. No bodies, loops or parallel requests.
- Never generate load. Load tests are for the human, on a disposable environment (item 15).

## Capacity formulas

Use these to turn "will it scale" into a number. Show the arithmetic in the report.

- **Throughput per process** = concurrency per process / avg response time (s).
  Example: 8 threads / 0.2 s = 40 req/s per process.
- **Processes needed** = peak req/s x avg response time (s) / concurrency per process, plus 30%
  headroom.
- **DB connections used** = replicas x processes per replica x pool size (+ workers x their
  pool + schedulers + migrations + admin). Must stay under `max_connections` minus about 10%.
- **Workers needed** (Little's law) = jobs per second x avg job duration (s). Queue lag grows
  without bound once arrival rate exceeds that.
- **Cache memory** = hot keys x avg value size x 1.3 overhead. Evictions start past `maxmemory`.
- **Third-party budget** = calls per user action x peak actions per minute. Compare with the
  provider's per-minute limit at 10x and 100x.
- **Breaks at** = limit / usage at today's peak. Below 10 means it breaks before 10x.
  Usage comes from item 0. CPU near 100% does not scale linearly: treat 70% as the practical
  limit.

## 0. Today's headroom (do this first)

- **Check**: peak utilization over the last 14 days for every component in the request path
  and background work. This is the "usage" term in "breaks at".
- **Evidence**: 14 days at `--period 3600` stays under the 1,440-datapoint limit. Then rerun
  once for the peak day only with `--period 60` to get the peak minute.
  - Run: `aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --dimensions Name=AutoScalingGroupName,Value=ASG_NAME --start-time START_ISO --end-time END_ISO --period 3600 --statistics Maximum`
  - Run: `aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name RequestCount --dimensions Name=LoadBalancer,Value=app/LB_NAME/LB_ID --start-time START_ISO --end-time END_ISO --period 3600 --statistics Sum`
  - Run: `aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name TargetResponseTime --dimensions Name=LoadBalancer,Value=app/LB_NAME/LB_ID --start-time START_ISO --end-time END_ISO --period 3600 --extended-statistics p99`
  - Run: `aws cloudwatch get-metric-statistics --namespace AWS/SQS --metric-name ApproximateAgeOfOldestMessage --dimensions Name=QueueName,Value=QUEUE_NAME --start-time START_ISO --end-time END_ISO --period 3600 --statistics Maximum`
  - Run: `aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name CPUUtilization --dimensions Name=DBInstanceIdentifier,Value=DB_ID --start-time START_ISO --end-time END_ISO --period 3600 --statistics Maximum`
  - Run: `aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name DatabaseConnections --dimensions Name=DBInstanceIdentifier,Value=DB_ID --start-time START_ISO --end-time END_ISO --period 3600 --statistics Maximum`
  - Run: `az monitor metrics list --resource RESOURCE_ID --metric 'Percentage CPU' --interval PT1H --aggregation Maximum --start-time START_ISO --end-time END_ISO`
  - Run: `mysql -e 'show global status like "Max_used_connections"'`
  - Run: `redis-cli INFO stats`
  - Run: `redis-cli INFO clients`
  - GCP: `gcloud monitoring` time-series reads are not on the guard's allow-list. Ask for a
    Metrics Explorer CSV export (14 days, max per hour) of Cloud Run request count and p99
    latency, instance count, CPU, and Cloud SQL CPU and connections.
  - Railway, Cloudflare, VPS: ask for a 14-day metrics screenshot or analytics export (CPU,
    memory, requests, p99). On a VPS, `docker stats --no-stream` is one sample, not a peak.
- **Breaks because**: without measured peaks every "breaks at" is a guess.
- **Fix**: none in code. If no metrics exist, the first finding is "no utilization metrics";
  mark load-derived rows `(unconfirmed)`.
- **Cost curve**: reads only. CloudWatch API reads cost about $0.01 per 1,000 metrics requested.

## 1. In-process state and sessions

- **Check**: sessions, caches, rate-limit counters, locks, WebSocket rooms or job state kept in
  process memory or on local files.
- **Evidence**: Grep `SESSION_DRIVER=file`, `session.*memory`, `MemoryStore`, `new Map\(`
  at module scope, `lru-cache`, `@lru_cache`, `static .*Dictionary`, `setInterval`,
  `node-cron`, `schedule:work`, `socket.io` without an adapter.
- **Breaks because**: a second replica (or a deploy that swaps containers) does not see the
  first one's memory. Users get logged out, rate limits multiply by replica count, crons run
  once per replica, sticky sessions pin hot users to one box.
- **Fix**: sessions and shared counters in Redis or the DB; scheduler as one separate service
  with a lock; pub/sub adapter for sockets. Keep per-process caches only for immutable data.
- **Cost curve**: one small managed Redis covers 10x and usually 100x. Cost is mostly the
  refactor, not the bill.

## 2. Local disk

- **Check**: uploads, generated files, SQLite, JSON data files or logs written to the
  container or instance filesystem.
- **Evidence**: Grep `storage/app`, `public/uploads`, `FILESYSTEM_DISK=local`, `sqlite`,
  `fs.writeFile`, `open\(.*'w'`, `VOLUME` in Dockerfiles, `volumes:` in compose, volume
  mounts in platform config.
- **Breaks because**: container disk is ephemeral and per-replica. A second replica cannot
  read files the first wrote; a deploy wipes them. Platform volumes usually attach to one
  service only, which blocks horizontal scaling and splits web from workers.
- **Fix**: object storage (S3, GCS, Azure Blob, R2) for files; a managed DB for data; workers
  read files by URL or key, never by local path.
- **Cost curve**: object storage is cents per GB; egress dominates at 100x, so serve media
  through a CDN.

## 3. Request path and app processes

- **Check**: process and thread count per replica, request timeout, autoscaling bounds,
  single replica, synchronous external calls inside requests.
- **Evidence**: Grep `workers`, `--threads`, `WEB_CONCURRENCY`, `pm.max_children`,
  `numReplicas`, `min_capacity`, `max_capacity`, `maxScale`, `timeout` in server config.
  - Run: `aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[].[AutoScalingGroupName,MinSize,MaxSize,DesiredCapacity]' --output table`
  - Run: `aws ecs describe-services --cluster CLUSTER --services SERVICE --query 'services[].[serviceName,desiredCount,runningCount]' --output table`
  - Run: `aws application-autoscaling describe-scalable-targets --service-namespace ecs --output table`
  - Run: `gcloud run services describe SERVICE --region REGION --format 'yaml(spec.template.metadata.annotations,spec.template.spec.containerConcurrency)'`
  - Run: `az appservice plan show --name PLAN --resource-group RG --query 'sku'`
  - Run: `kubectl get hpa -A`
  - Run: `kubectl top pods -A`
  - Run: `railway status --json`
  - Run: `docker stats --no-stream`
  - `kubectl top` and `docker stats --no-stream` are single samples: run once, use item 0 for
    peaks.
- **Breaks because**: a fixed pool of processes saturates at the throughput formula; extra
  requests queue, then time out. A max replica count of 1 to 3 is a hard ceiling. One slow
  upstream call ties up a worker for its full timeout.
  - **Autoscaling lag**: scale-out takes minutes (metric period + boot + warm-up). A spike
    that doubles traffic in 30 s is served by today's replicas alone.
  - **Thundering herd on deploy or restart**: all replicas start cold together, caches are
    empty, every client reconnects and retries at once.
  - **Memory, OOM and file descriptors**: long-lived connections (WebSockets, SSE, streaming)
    hold memory and one FD each; 10x connections hit the container memory limit or `ulimit -n`.
  - **Timeouts, retries and backpressure between services**: a caller timeout longer than the
    callee's, or retries at every layer, multiplies load on the slowest service. Without a
    bounded queue or 503, overload turns into a pile-up.
- **Fix**: autoscale on CPU or concurrency with a max that covers 10x; set upstream timeouts
  under the request timeout; move slow work to a queue and return 202. Pre-scale before known
  spikes (min replicas); rolling deploys with warm-up and jittered client reconnects; size
  memory and `ulimit -n` per connection; retry at one layer only, with a budget, and shed load
  with 503 plus `Retry-After`.
- **Cost curve**: roughly linear in replicas. Check the platform's plan or hard compute limit:
  hitting it takes every service down at once.

## 4. N+1 queries and per-request query count

- **Check**: loops that query per item, lazy-loaded relations in lists, serializers that touch
  relations, GraphQL resolvers without a loader.
- **Evidence**: Grep `foreach.*->load`, `\.map\(async`, `findOne` inside loops,
  `\.objects\.get\(` inside a `for` body (search for each, then read the loop),
  `->count\(\)` in views, missing `with\(`/`includes`/`select_related`/`prefetch_related`/
  `DataLoader`.
  - Run (PostgreSQL 13+): `psql -c 'select calls, round(mean_exec_time) as ms, substring(query, 1, 80) as q from pg_stat_statements order by calls desc limit 20'`
  - Run (PostgreSQL 12 and older): `psql -c 'select calls, round(mean_time) as ms, substring(query, 1, 80) as q from pg_stat_statements order by calls desc limit 20'`
  - Run: `mysql -e 'select digest_text, count_star from performance_schema.events_statements_summary_by_digest order by count_star desc limit 20'`
- **Breaks because**: query count grows with page size and traffic together. 50 rows x 3
  relations = 151 queries per request; at 10x traffic the DB sees 10x of that.
- **Fix**: eager-load, batch with `IN`, add a loader, paginate. Turn on lazy-loading
  violations in dev/test (for example `preventLazyLoading`).
  For per-request detail, use `performance-review`.
- **Cost curve**: free to fix in code; otherwise it forces a DB size jump (2x price per tier)
  long before real load does. Index and `EXPLAIN` depth: `database-review`.

## 5. DB connections and pooling

- **Check**: pool size per process, number of processes and replicas, serverless fan-out,
  pooler in front (PgBouncer, RDS Proxy, Supavisor), `max_connections`.
- **Evidence**: Grep `pool`, `max_connections`, `DB_POOL`, `connection_limit`,
  `pgbouncer`, `aws_db_proxy`, `pool_mode`.
  - Run: `psql -c 'show max_connections'`
  - Run: `psql -c 'select state, count(*) from pg_stat_activity group by state'`
  - Run: `mysql -e 'show global status like "Max_used_connections"'`
  - Run: `mysql -e 'show variables like "max_connections"'`
  - `pg_stat_activity` is an instant sample; the peak comes from the CloudWatch query below or
    item 0.
  - Run: `aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,MultiAZ]' --output table`
  - Run: `aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name DatabaseConnections --dimensions Name=DBInstanceIdentifier,Value=DB_ID --start-time START_ISO --end-time END_ISO --period 3600 --statistics Maximum`
  - Run: `gcloud sql instances describe INSTANCE --format 'yaml(settings.tier,settings.databaseFlags)'`
  - Run: `az postgres flexible-server show --name SERVER --resource-group RG --query 'sku'`
- **Breaks because**: connections multiply with replicas (formula above). Autoscaling web to
  10x replicas multiplies connections by 10 and the DB refuses new ones. Lambda/Cloud Run
  fan-out hits this fastest. A worker pool smaller than worker concurrency + 1 can stall or
  time out when every thread waits for a connection while one more is held (for example by a
  nested transaction or a listener).
  - **Read-replica lag**: replicas fall behind under write load; read-after-write paths on a
    replica show stale data. Check `ReplicaLag` (RDS) or `pg_stat_replication`.
- **Fix**: a transaction-mode pooler; small per-process pools (about 5 for serverless); cap
  autoscaling so connections stay under the limit; read replicas for heavy reads, with
  read-after-write paths pinned to the primary.
- **Cost curve**: a pooler is cheap (RDS Proxy is billed per vCPU of the DB). Raising
  `max_connections` usually means a bigger instance, about 2x per tier.

## 6. Cache stampede and hit ratio

- **Check**: hot keys that expire together, cache-aside without a lock, full rendered pages
  or large blobs in a DB-backed cache, per-item cache writes on index pages, eviction policy.
- **Evidence**: Grep `Cache::remember`, `cache.get_or_set`, `getOrSet`, `ttl`, `expire`,
  `CACHE_STORE=database`, `CACHE_DRIVER`, `maxmemory`.
  - Run: `redis-cli INFO stats`
  - Run: `redis-cli INFO memory`
  - Run: `redis-cli CONFIG GET maxmemory-policy`
  - Run: `curl -sI https://example.com/ | grep -i cf-cache-status`
- **Breaks because**: when a hot key expires, every concurrent request recomputes it at once
  and the DB spikes. `evicted_keys` rising or a low `keyspace_hits` ratio means the cache is
  too small. A DB-backed cache adds load to the thing it should protect.
- **Fix**: lock or single-flight on recompute, stale-while-revalidate, jittered TTLs, cache
  metadata not whole pages, a real cache store (Redis/Memcached) once the DB is the bottleneck.
  Put public pages behind CDN edge cache with a bypass for auth cookies.
- **Cost curve**: cache memory is cheap; an edge cache hit costs nothing at origin, so a high
  CDN hit ratio flattens the curve more than any instance upgrade.

## 7. Queues and worker capacity

- **Check**: queue driver, worker count and concurrency, job timeout vs retry/visibility
  timeout, separate queues for slow jobs, DLQ, backlog age.
- **Evidence**: Grep `retry_after`, `VisibilityTimeout`, `visibility_timeout`, `--timeout`,
  `--tries`, `concurrency`, `QUEUE_CONNECTION`, `onQueue`, `redrive_policy`, `deadLetter`.
  - Run: `aws sqs get-queue-attributes --queue-url QUEUE_URL --attribute-names All`
  - Run: `aws lambda get-function-concurrency --function-name FUNCTION`
  - Run: `redis-cli LLEN QUEUE_KEY`
  - Run: `psql -c "select relname, n_live_tup from pg_stat_user_tables where relname in ('jobs', 'failed_jobs')"`
  - That is an estimate with no table scan. Per-queue counts need `count(*)` on the jobs
    table: run on a replica only, or put it in "Commands for you to run".
- **Breaks because**: Little's law. At 10x arrivals the same workers fall behind and lag
  grows forever. If retry/visibility is shorter than the longest job, a slow job is redelivered
  while still running and runs twice. One shared queue lets a slow job type starve the rest.
  A database queue driver adds polling load to the primary DB.
- **Fix**: workers sized by the formula and autoscaled on queue depth or age; retry/visibility
  above the longest job timeout; one queue per slow job type or webhook provider; idempotent
  jobs (unique key, overlap lock longer than the timeout); a DLQ with an alert; graceful
  shutdown with drain time above the longest job.
- **Cost curve**: linear in workers. Move from a DB queue to Redis or SQS only when the DB
  queue's polling shows up in DB load; Kafka/NATS only when one Redis is outgrown.

## 8. Schedulers and singletons

- **Check**: cron or scheduler running inside every web replica, overlapping deploys running a
  singleton twice, jobs that scan whole tables.
- **Evidence**: Grep `schedule:run`, `schedule:work`, `node-cron`, `APScheduler`, `celery beat`,
  `withoutOverlapping`, `onOneServer`, `pg_advisory_lock`, `cron` in platform config.
- **Breaks because**: scaling web to N replicas runs every cron N times. A nightly full-table
  job that takes 5 minutes today takes 50 at 10x data and overlaps the next run.
- **Fix**: one scheduler service with a lock; batch or incremental jobs (`SKIP LOCKED`, cursor
  by id); jobs fan out into the queue instead of doing the work inline.
- **Cost curve**: one small service; flat.

## 9. Third-party API rate limits

- **Check**: calls to payment, email, SMS, AI/LLM, maps, search or social APIs in the request
  path or per item in jobs; retry policy; 429 handling.
- **Evidence**: Grep HTTP client calls (`Http::`, `axios`, `fetch\(`, `requests\.`, `httpx`,
  SDK clients), `retry`, `backoff`, `429`, `Retry-After`, `RateLimiter`.
- **Breaks because**: provider limits are fixed per key or plan, not per your replica. 10x
  traffic hits a per-minute cap, retries without backoff turn 429s into a storm, and a slow
  provider holds request workers.
- **Fix**: shared token bucket in Redis per provider; retry once with backoff only on timeouts,
  408/429/5xx, honoring `Retry-After`; batch endpoints; move calls to a queue; cache results by
  input hash; for LLM calls, prompt caching and per-plan caps.
- **Cost curve**: usually per call, so linear or worse at tier jumps. LLM and SMS costs often
  dominate the 10x bill; convert to cost per request before setting quotas.

## 10. Write contention and hot rows

- **Check**: counters updated on one row, `max + 1` id or sequence logic, global locks,
  long transactions around external calls.
- **Evidence**: Grep `increment\(`, `UPDATE .* SET .* = .* \+ 1`, `lockForUpdate`,
  `select_for_update`, `max\(id\)`, transactions wrapping HTTP calls.
  - Run: `psql -c 'select count(*) from pg_locks where not granted'`
  - One sample. A non-zero count at a busy moment points at contention; confirm with lock waits
    in the slow-query log.
- **Breaks because**: row locks serialize writers. Throughput on a hot row stays flat no matter
  how many replicas you add.
- **Fix**: sharded counters or append-only events summed later; DB sequences or UUIDv7;
  keep external calls outside transactions.
- **Cost curve**: code-only fix; hardware does not help.

## 11. Edge, CDN and abuse

- **Check**: static and media served from origin, no CDN, no rate limit on login, signup,
  search or webhook endpoints, origin reachable directly.
- **Evidence**: Grep `Cache-Control`, `immutable`, `ASSET_URL`, `throttle`, `rate_limit`,
  `limit_req`, WAF rules in IaC.
  - Run: `curl -sI https://example.com/ | grep -i cache-control`
  - Edge rate-limit rules: read them from IaC, or ask for a WAF/rate-limit rules export.
- **Breaks because**: at 100x, bandwidth and bot traffic hit origin directly; one expensive
  unauthenticated endpoint becomes the easiest way to take the site down.
- **Fix**: CDN for hashed assets and media with long TTLs; edge rate limits on expensive public
  routes; app-level rate limits backed by shared state. Origin hardening: `infra-review`.
- **Cost curve**: CDN egress is far cheaper than cloud origin egress; the gap grows with
  traffic.

## 12. Data growth

- **Check**: tables and buckets that grow with users or events, no retention, unbounded
  `SELECT` without `LIMIT`, offset pagination on large tables, exports built in memory.
- **Evidence**: Grep `->get\(\)` / `.all\(\)` without limits, `OFFSET`, `paginate\(`,
  `toArray\(\)` on large queries, logs or events tables with no prune job.
  - Run: `psql -c 'select relname, n_live_tup, pg_size_pretty(pg_total_relation_size(relid)) from pg_stat_user_tables order by n_live_tup desc limit 15'`
  - Catalog reads only, cheap. Size functions stat every file of each table, so run once and
    keep the `limit`.
- **Breaks because**: 100x data turns full scans and offset pages into seconds-long queries
  and memory spikes, even when traffic is flat.
- **Fix**: keyset pagination, streaming exports, retention and pruning jobs, archive to object
  storage. Index work: `database-review`.
- **Cost curve**: storage is cheap; the cost is in compute for scans and bigger instances.

## 13. Platform ceilings

- **Check**: plan limits and hard caps that are not autoscaling: Railway hard compute limit and
  per-service replica caps, Cloudflare Worker CPU and script size, Cloud Run max instances,
  App Service plan instance count, Lambda account concurrency, Kubernetes node pool max.
- **Evidence**: platform config files and IaC (`maxScale`, `max_instance_count`,
  `reserved_concurrent_executions`, `max_size`, node pool `max_count`).
  - Run: `aws lambda get-account-settings --query 'AccountLimit'`
  - Run: `gcloud run services list --format 'table(metadata.name,spec.template.metadata.annotations)'`
  - Run: `kubectl get nodes -o wide`
- **Breaks because**: the cap, not the code, sets the ceiling. A spend or compute hard limit
  stops every service together. AWS quotas in depth: `aws-bottleneck-review`.
- **Fix**: raise caps ahead of the event with a spend alert; request quota increases days
  early; load test in a disposable environment, never production.
- **Cost curve**: step function at plan tiers; note the next tier's price in the report.

## 14. Cost curve per 10x

For each target, estimate the monthly bill and name what drives it:

- **Linear**: app replicas, workers, per-call APIs, egress.
- **Hidden linear**: NAT gateway data processing (per GB, on top of egress), cross-AZ traffic,
  and log and metrics ingestion. 10x requests at DEBUG logging can cost more than the compute.
- **Step**: DB and cache instance tiers (about 2x per step), platform plan tiers, support plans.
- **Flat**: CDN-cached traffic, poolers, code fixes (N+1, in-process state, stampede locks).
- If 10x costs more than 10x today's bill, the architecture is the problem, not the traffic:
  list the item that bends the curve.
- Show the arithmetic per row in the "Breaks first" table. Write "n/a" when a price is unknown.

## 15. Load-test plan for the human

The review never runs load. When a break point needs proof, write a plan into "Commands for
you to run":

- **Tool**: k6, Locust, Gatling or `hey`, scripted against the real user flows, not one URL.
- **Target**: a disposable environment with its own DB, cache and queue, production-sized data,
  synthetic users, third-party calls stubbed or in sandbox mode, a spend cap and a teardown
  date. Never production.
- **Ramp**: step from 1x to 3x, 10x (and 100x if the target asks) of today's peak, holding
  each step 5 to 10 minutes; add one spike step (0 to 10x in 30 s) to test autoscaling lag.
- **Watch**: p99 latency, error rate, DB connections and CPU, queue age, cache evictions.
- **Stop criteria**: p99 above the SLO for 2 minutes, error rate above 1%, DB connections above
  90% of the limit, or spend cap reached. Record the step where each limit hit: that is the
  measured "breaks at".
