# Database review checklist

Each item: **Check**, **Evidence** (grep and/or read-only command), **Why**, **Fix**,
**$/mo** where it can be estimated. Every command here passes the read-only guard as written.

Placeholders: `APP_DB` (database/schema name), `TABLE`, `DB_ID` (RDS instance id),
`CLUSTER_ID`, `PARAM_GROUP`, `REPL_GROUP`, `REGION`, `START_ISO`/`END_ISO`
(e.g. `2026-01-01T00:00:00Z`), `START_DATE`/`END_DATE` (e.g. `2026-01-01`).

Prices are us-east-1 list prices at time of writing. Confirm against the user's bill or the
AWS pricing page before quoting. Show the arithmetic.

Run every psql line as `PGOPTIONS=-cdefault_transaction_read_only=on psql -X -c "select ..."`.
The prefix is omitted below for length.

An empty result or an error (view missing, feature off, no privilege) means "unavailable",
not "no problems". Record it as a missing input and use the item's fallback. The monitoring
roles from SKILL.md see statistics, not table data, and `information_schema` only lists
objects the user can access.

## PostgreSQL

### PG1. Top queries by total time
- **Check:** which statements dominate DB time; then `explain` each.
- **Evidence:** `psql -X -c "select extname, extversion from pg_extension"` (needs `pg_stat_statements`).
  `psql -X -c "select calls, round(total_exec_time) as total_ms, round(mean_exec_time) as mean_ms, rows, substring(query from 1 for 120) as q from pg_stat_statements order by total_exec_time desc limit 20"`.
  PG 12 and older: `total_time`/`mean_time`. Then `psql -X -c "explain select ..."` with the real query (needs `SELECT` on the table).
  Query text is normalized, but comments and utility statements can still carry literals: redact values before quoting a query in the report.
- **Why:** a few queries usually cause most of the load; fixing them beats a bigger instance.
- **Fix:** add the index the plan needs, rewrite the query, or cache the result. If the extension is missing: RDS/Aurora already preload it, so the human runs `create extension pg_stat_statements`; self-hosted also needs `shared_preload_libraries = 'pg_stat_statements'` and a restart.
- **$/mo:** if fixing it allows a smaller instance, the class price difference (see RDS1).

### PG2. Sequential scans on big tables (missing indexes)
- **Check:** tables with many rows read by seq scan.
- **Evidence:** `psql -X -c "select relname, seq_scan, seq_tup_read, idx_scan, n_live_tup from pg_stat_user_tables where n_live_tup > 100000 order by seq_tup_read desc limit 20"`.
  Grep app code for filters on those tables: `grep -rnE 'where|orderBy|filter_by|findBy' --exclude-dir=node_modules --exclude-dir=vendor app src`.
- **Why:** each request reads the whole table; latency grows with data.
- **Fix:** `create index concurrently` on the filter + sort columns, in a migration that runs outside a transaction (see MIG2). Check that a composite index matches the list filters actually used, not just `(tenant_id, created_at)`.

### PG3. Foreign keys without an index
- **Check:** FK columns with no index leading on them.
- **Evidence:** `psql -X -c "select c.conrelid::regclass as tbl, c.conname from pg_constraint c where c.contype = 'f' and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and i.indkey[0] = c.conkey[1])"` (checks the first column only).
- **Why:** deleting or updating a parent row scans the child table and holds locks.
- **Fix:** `create index concurrently on child (fk_col)`.

### PG4. Unused and duplicate indexes
- **Check:** indexes never scanned, and identical indexes on the same columns.
- **Evidence:** `psql -X -c "select datname, stats_reset from pg_stat_database"` (stats window).
  `psql -X -c "select s.relname, s.indexrelname, s.idx_scan, pg_size_pretty(pg_relation_size(s.indexrelid)) as size from pg_stat_user_indexes s join pg_index i on i.indexrelid = s.indexrelid where s.idx_scan = 0 and not i.indisunique and not i.indisprimary order by pg_relation_size(s.indexrelid) desc limit 20"`.
  `psql -X -c "select indrelid::regclass as tbl, indkey::text as cols, count(*) from pg_index group by indrelid, indkey::text, indclass::text, coalesce(indpred::text, ''), coalesce(indexprs::text, '') having count(*) > 1"`.
- **Why:** each index slows every write and costs storage and memory. Stats are per node: an index unused on the primary may serve a replica. Confirm on each replica and over at least one full business cycle.
- **Fix:** `drop index concurrently` in a migration, after checking replicas.
- **$/mo:** index GB x storage price, e.g. 40 GB x $0.115 (RDS gp3) = $4.60, plus write I/O on Aurora Standard.

### PG5. Connections and pooling
- **Check:** connection count vs `max_connections`; pool size per service vs concurrency.
- **Evidence:** `psql -X -c "show max_connections"`. `psql -X -c "select usename, application_name, state, count(*) from pg_stat_activity group by usename, application_name, state order by count(*) desc"`.
  Grep: `grep -rnE 'pool|max_connections|DB_POOL|pgbouncer|connection_limit|CONN_MAX_AGE' --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git .`
- **Why:** sum of (replicas x pool size) above `max_connections` fails at the next scale-out or deploy overlap. A worker pool smaller than worker concurrency + 1 deadlocks jobs. Lambda fan-out opens one pool per concurrent invocation.
- **Fix:** size each pool to at least its concurrency + 1, keep the total under about 80% of `max_connections`, put PgBouncer (transaction mode) or RDS Proxy in front for many short-lived clients.

### PG6. Idle in transaction and long transactions
- **Check:** sessions holding a transaction open.
- **Evidence:** `psql -X -c "select pid, state, now() - xact_start as xact_age, substring(query from 1 for 80) as q from pg_stat_activity where xact_start is not null order by xact_start limit 10"`.
  `psql -X -c "select name, setting from pg_settings where name in ('idle_in_transaction_session_timeout', 'statement_timeout', 'lock_timeout')"`.
- **Why:** long transactions block vacuum (bloat) and hold locks that queue every later ALTER.
- **Fix:** set `idle_in_transaction_session_timeout` (e.g. 60s) and a per-role `statement_timeout`; keep external calls out of transactions.

### PG7. Lock waits
- **Check:** sessions waiting on locks right now.
- **Evidence:** `psql -X -c "select locktype, mode, relation::regclass as rel, pid from pg_locks where not granted"`.
  `psql -X -c "select pid, wait_event_type, wait_event, state, now() - query_start as runtime from pg_stat_activity where wait_event_type is not null and state <> 'idle'"`.
- **Why:** one blocked ALTER makes every later query on that table wait behind it.
- **Fix:** find the blocker (`pg_blocking_pids`, see Commands for you to run), shorten its transaction, add `lock_timeout` to migrations.

### PG8. Autovacuum and bloat
- **Check:** dead tuples piling up; autovacuum not keeping up.
- **Evidence:** `psql -X -c "select relname, n_live_tup, n_dead_tup, last_autovacuum, last_autoanalyze from pg_stat_user_tables order by n_dead_tup desc limit 20"`. `psql -X -c "show autovacuum"`.
- **Why:** bloat makes every scan slower and the disk bigger; stale stats give bad plans.
- **Fix:** per-table `autovacuum_vacuum_scale_factor = 0.02` on hot tables, end long transactions (PG6), `pg_repack` for heavy bloat (command for the human).
- **$/mo:** reclaimed GB x storage price.

### PG9. Transaction ID wraparound
- **Check:** XID age per database.
- **Evidence:** `psql -X -c "select datname, age(datfrozenxid) as xid_age from pg_database order by 2 desc"`.
- **Why:** near 2 billion Postgres stops accepting writes. Over 500 million is High, over 1 billion Critical.
- **Fix:** find what blocks freezing (long transactions, inactive slots, PG10), run `vacuum freeze` on the oldest tables (command for the human).

### PG10. Replication slots retaining WAL
- **Check:** inactive slots and how much WAL they hold.
- **Evidence:** `psql -X -c "select slot_name, slot_type, active, restart_lsn, wal_status, safe_wal_size from pg_replication_slots"` (PG13+; older: drop the last two columns). `psql -X -c "show max_slot_wal_keep_size"`.
  Retained bytes per slot need `pg_wal_lsn_diff`: put `select slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) from pg_replication_slots` in Commands for you to run.
- **Why:** an inactive slot keeps all WAL; the disk fills and the DB stops. `wal_status = 'extended'` or `'unreserved'` is close to the edge; `max_slot_wal_keep_size = -1` means no cap.
- **Fix:** drop slots for dead consumers (`select pg_drop_replication_slot('name')`, command for the human); set `max_slot_wal_keep_size`; alert on slot lag.

### PG11. Backups and PITR (self-hosted or platform)
- **Check:** WAL archiving really works; a logical dump exists off-platform; a restore was tested.
- **Evidence:** `psql -X -c "show archive_mode"`. `psql -X -c "select archived_count, failed_count, last_archived_time, last_failed_time from pg_stat_archiver"`.
  Grep: `grep -rnE 'pg_dump|pg_basebackup|wal-g|pgbackrest|barman|backup' --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git .`
  On managed platforms, read the backup list and schedule back, do not trust the toggle.
- **Why:** "PITR on" with `archive_mode=off`, or zero backups and zero schedules, is common. PITR starts at the first base backup, not before. Daily snapshots cannot meet a 15-minute RPO.
- **Fix:** platform PITR plus a nightly `pg_dump` to an external bucket with a 30-day lifecycle, and a monthly restore drill into a scratch instance that compares table counts, columns and constraints. State RPO/RTO from the drill, not from docs.

### PG12. Key settings
- **Check:** memory and planner settings fit the instance.
- **Evidence:** `psql -X -c "select name, setting, unit from pg_settings where name in ('shared_buffers', 'work_mem', 'effective_cache_size', 'random_page_cost', 'max_connections', 'maintenance_work_mem')"`.
  `psql -X -c "select sum(heap_blks_hit) / greatest(sum(heap_blks_hit) + sum(heap_blks_read), 1) as hit_ratio from pg_statio_user_tables"`.
- **Why:** `random_page_cost = 4` on SSD steers plans away from indexes; hit ratio under 0.99 on OLTP means the working set does not fit in memory.
- **Fix:** `random_page_cost = 1.1` on SSD; size `shared_buffers` about 25% of RAM; fix queries before buying RAM.

### PG13. Biggest tables and growth
- **Check:** largest relations; time-series or log tables with no retention.
- **Evidence:** `psql -X -c "select relname, n_live_tup, pg_size_pretty(pg_total_relation_size(relid)) as total from pg_stat_user_tables order by pg_total_relation_size(relid) desc limit 20"`.
- **Why:** sizes decide which migrations are dangerous (MIG*) and where storage money goes.
- **Fix:** retention job, partitioning by time, or archive to object storage.
- **$/mo:** GB removed x storage price.

### PG14. Database used as cache, queue and session store
- **Check:** cache/jobs/sessions tables in the primary DB.
- **Evidence:** `grep -rnE 'CACHE_STORE=database|CACHE_DRIVER=database|SESSION_DRIVER=database|QUEUE_CONNECTION=database|SKIP LOCKED' --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git .`
  Sizes of `cache`, `jobs`, `sessions` tables via PG13.
- **Why:** fine at small scale, but it couples everything to one volume. Large cached blobs (full HTML) make reads slow; per-item cache writes on list pages cause write storms.
- **Fix:** cache metadata only, version cache keys when the cached shape changes, move cache/queue to Redis when it shows in PG1.

### PG15. Concurrency correctness
- **Check:** upserts and job queues hold up with two writers.
- **Evidence:** `grep -rnE 'ON CONFLICT|upsert|updateOrCreate|SKIP LOCKED|advisory_lock|unique' --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git .`
- **Why:** a unique index on a nullable column lets duplicate NULL rows in; a `SKIP LOCKED` lease that is not extended lets a stalled job run twice; two scheduler replicas without an advisory lock double-run.
- **Fix:** `unique nulls not distinct` (PG15+) or a partial unique index; extend leases while a job runs and fence writes with a lease counter; `pg_try_advisory_lock` for singletons; write multi-step state changes in one transaction.

### PG16. Timestamps and CI engine
- **Check:** `timestamp without time zone` columns; CI testing on another engine.
- **Evidence:** `psql -X -c "select c.relname, a.attname from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace where a.atttypid = 'timestamp'::regtype and c.relkind = 'r' and n.nspname not in ('pg_catalog', 'information_schema') and not a.attisdropped"`.
  `grep -rnE 'DB_CONNECTION|sqlite' .github phpunit.xml` and, for the env file, name only:
  `grep -l 'DB_CONNECTION=sqlite' .env.testing`
- **Why:** naive timestamps break across DST and servers. SQLite in CI hides Postgres-only failures (unique index scope, `down()` migrations, triggers, CHECKs).
- **Fix:** `timestamptz` stored in UTC; run CI on the same engine and major version as production, with per-worker databases.

### PG17. Version and extensions
- **Check:** major version support window; pgvector indexes.
- **Evidence:** `psql -X -c "select version()"`. `psql -X -c "select indexname, indexdef from pg_indexes where indexdef like '%hnsw%' or indexdef like '%ivfflat%'"`.
- **Why:** an EOL major gets no fixes and, on RDS, costs Extended Support (RDS9). Vector columns without an ANN index scan every row.
- **Fix:** plan the major upgrade (blue/green on RDS); HNSW index (`m = 16, ef_construction = 200` works to about 500K vectors).

### PG18. Integer key and sequence exhaustion
- **Check:** `int4` keys and sequences close to 2,147,483,647.
- **Evidence:** `psql -X -c "select schemaname, sequencename, data_type, last_value, max_value, round(100.0 * last_value / max_value, 1) as pct from pg_sequences where last_value is not null order by 6 desc limit 20"` (`last_value` is null without sequence privileges: then unavailable).
  `psql -X -c "select c.relname, a.attname from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_index i on i.indrelid = c.oid and i.indisprimary and a.attnum = i.indkey[0] where a.atttypid = 'int4'::regtype"`.
  Migrations: `grep -rnE 'increments[(]|serial|integer primary key|INT AUTO_INCREMENT' database/migrations db/migrate migrations prisma drizzle`
- **Why:** at the limit every insert fails. Over 50% is High, over 80% Critical; the `bigint` change rewrites the table.
- **Fix:** add a `bigint` column, backfill in batches, swap in a short lock (expand/contract); new tables use `bigint`/`bigserial` or UUIDv7.

### PG19. Replica lag and temp-file spill
- **Evidence:** on the primary: `psql -X -c "select application_name, state, write_lag, flush_lag, replay_lag from pg_stat_replication"`.
  `psql -X -c "select datname, temp_files, pg_size_pretty(temp_bytes) as temp_size, stats_reset from pg_stat_database"`.
- **Why:** reads routed to a lagging replica return stale data (read-your-writes bugs). Large `temp_bytes` means sorts and hashes spill to disk because `work_mem` is too small for those queries.
- **Fix:** alert on lag (RDS `ReplicaLag`, see RDS13), route read-after-write to the primary; raise `work_mem` per role or per query, or add the index that avoids the sort; `log_temp_files = 0` to find the queries.

## MySQL/MariaDB

Pre-check first: `mysql -e "select version()"` and `mysql -e "show variables like 'performance_schema'"`.
MariaDB ships `performance_schema` off and has `sys` only from 10.6; RDS MySQL often has it off on
small classes; MariaDB has no `performance_schema.data_lock_waits`. When `performance_schema` is OFF
or `sys` is missing, MY1-MY3 and MY6 queries return nothing or error: mark them unavailable and use
the fallbacks listed in each item.

### MY1. Top statements
- **Check:** statement digests by total time and rows examined.
- **Evidence:** `mysql -e "select substring(digest_text, 1, 120) as q, count_star, round(sum_timer_wait / 1000000000000) as total_s, sum_rows_examined, sum_no_index_used from performance_schema.events_statements_summary_by_digest order by sum_timer_wait desc limit 20"`.
  `mysql -e "show variables like 'slow_query%'"`. `mysql -e "show variables like 'long_query_time'"`.
  Fallback without `performance_schema`: the slow log. `mysql -e "show variables like 'slow_query_log_file'"`, then ask the user for the file or `pt-query-digest` output (RDS: `aws rds describe-db-log-files --db-instance-identifier DB_ID`; downloading is a command for the human).
- **Why:** rows examined far above rows sent means a missing index.
- **Fix:** add the index from `mysql -e "explain select ..."`; enable the slow log with `long_query_time = 1`; turn `performance_schema` on (restart) where memory allows.

### MY2. Full table scans
- **Evidence:** `mysql -e "select * from sys.statements_with_full_table_scans limit 20"`.
  Fallback: `mysql -e "show global status like 'Handler_read_rnd_next'"`, `mysql -e "show global status like 'Select_full_join'"`, `mysql -e "show global status like 'Select_scan'"`, compared with `mysql -e "show global status like 'Questions'"` and the slow log. A high and growing `Handler_read_rnd_next` or any steady `Select_full_join` means unindexed reads.
- **Why / Fix:** as PG2. Build indexes online (MIG2).

### MY3. Unused and redundant indexes
- **Evidence:** prefer a replica that serves reads, and check every replica: usage is per server. `mysql -e "select * from sys.schema_unused_indexes"`. `mysql -e "select table_name, redundant_index_name, dominant_index_name from sys.schema_redundant_indexes"`.
  Fallback without `sys`: none for unused indexes (mark unavailable); redundant ones by reading `mysql -e "show index from TABLE"`.
- **Why:** writes and buffer pool memory spent on indexes nobody reads. Stats reset on restart: check uptime with `mysql -e "show global status like 'Uptime'"`.
- **Fix:** `alter table ... drop index ..., algorithm=inplace, lock=none` (command for the human).
- **$/mo:** index GB x storage price.

### MY4. Tables without a primary key, and charset
- **Evidence:** `mysql -e "select t.table_name from information_schema.tables t left join information_schema.table_constraints c on c.table_schema = t.table_schema and c.table_name = t.table_name and c.constraint_type = 'PRIMARY KEY' where t.table_schema = 'APP_DB' and t.table_type = 'BASE TABLE' and c.constraint_name is null"`.
  `mysql -e "select table_name, table_collation from information_schema.tables where table_schema = 'APP_DB' and table_collation not like 'utf8mb4%'"`.
- **Why:** no PK breaks row-based replication performance, Group Replication and blue/green; `utf8` (3-byte) loses emoji and some scripts.
- **Fix:** add PKs; convert to `utf8mb4` online for big tables.

### MY5. Connections
- **Evidence:** `mysql -e "show variables like 'max_connections'"`. `mysql -e "show global status like 'Max_used_connections'"`. `mysql -e "show global status like 'Threads_connected'"`. `mysql -e "show global status like 'Aborted_connects'"`.
- **Why / Fix:** as PG5. `Max_used_connections` near `max_connections` means the next spike fails.

### MY6. Long transactions and purge lag
- **Evidence:** `mysql -e "select trx_id, trx_started, trx_state, trx_rows_locked from information_schema.innodb_trx order by trx_started limit 10"`.
  `mysql -e "select name, count from information_schema.innodb_metrics where name = 'trx_rseg_history_len'"`.
  MySQL 8: `mysql -e "select * from performance_schema.data_lock_waits limit 20"`. MariaDB and MySQL 5.7: `mysql -e "select * from information_schema.innodb_lock_waits"`.
  Fallback for all: `mysql -e "show engine innodb status"` (`TRANSACTIONS` section: history list length, lock waits, oldest transaction).
- **Why:** a long transaction grows the undo history; every read slows and lock waits pile up.
- **Fix:** shorter transactions; `innodb_lock_wait_timeout`; app-side timeouts.

### MY7. Buffer pool and table sizes
- **Evidence:** `mysql -e "show variables like 'innodb_buffer_pool_size'"`. `mysql -e "show global status like 'Innodb_buffer_pool_read%'"`.
  `mysql -e "select table_name, table_rows, round((data_length + index_length) / 1024 / 1024) as mb, round(data_free / 1024 / 1024) as free_mb from information_schema.tables where table_schema = 'APP_DB' order by data_length + index_length desc limit 20"`.
- **Why:** `Innodb_buffer_pool_reads` / `read_requests` above 1% means disk reads on the hot path. Big `free_mb` is reclaimable fragmentation.
- **Fix:** buffer pool about 70% of RAM on a dedicated host; `optimize table` off-peak (command for the human).

### MY8. Backups and binlog
- **Evidence:** `mysql -e "show variables like 'log_bin'"`. `mysql -e "show variables like 'binlog_expire_logs_seconds'"` (MariaDB before 10.6 and MySQL 5.7: `mysql -e "show variables like 'expire_logs_days'"`). RDS MySQL: binlog retention hours come from `call mysql.rds_show_configuration` (command for the human).
  `grep -rnE 'mysqldump|mariadb.dump|xtrabackup|mariabackup|backup' --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git .`
- **Why:** no binlog means no point-in-time recovery; dumps never restored are not backups.
- **Fix:** binlog on with retention covering the backup interval; nightly dump off-host; restore drill.

### MY9. Engine pinning and container setup
- **Evidence:** `grep -rnE 'image: *(mysq|mariad)|depends_on|service_healthy|mysqldump' --include='*.yml' --include='*.yaml' --exclude-dir=node_modules --exclude-dir=.git .`
- **Why:** `mariadb:latest` (11+) drops the `mysql`/`mysqldump` binaries scripts call; MySQL 8-only features (`performance_schema.data_lock_waits`) differ. App start without a healthcheck races the DB.
- **Fix:** pin the image major you support; `depends_on: { db: { condition: service_healthy } }`.

### MY10. Database on the app host
- **Evidence:** `grep -rnE 'user_data|mysql.server|mariadb.server' --include='*.tf' --include='*.sh' --include='*.yml' --exclude-dir=node_modules --exclude-dir=.git . | cut -d: -f1,2` (file:line only: user data can hold passwords)
- **Why:** DB on the app instance with credentials in `user_data` and no backups is a single point of failure and a secret leak.
- **Fix:** managed DB (or a dedicated host with backups); credentials from a secrets manager.

### MY11. Integer key exhaustion, replica lag, temp tables
- **Evidence:** `mysql -e "select table_name, auto_increment from information_schema.tables where table_schema = 'APP_DB' and auto_increment > 1000000000 order by auto_increment desc"` (signed `int` max 2,147,483,647).
  `mysql -e "select table_name, column_name, column_type from information_schema.columns where table_schema = 'APP_DB' and column_key = 'PRI' and data_type = 'int'"`.
  `mysql -e "show replica status"` (MySQL 8.0.22+; older and MariaDB: `mysql -e "show slave status"`), field `Seconds_Behind_Source`/`Seconds_Behind_Master`.
  `mysql -e "show global status like 'Created_tmp%'"`.
- **Why:** an `int` key at its limit stops inserts; lagging replicas serve stale reads; `Created_tmp_disk_tables` above about 10% of `Created_tmp_tables` means sorts spill to disk.
- **Fix:** `bigint` via online DDL (gh-ost/pt-osc); alert on lag (RDS13); raise `tmp_table_size`/`max_heap_table_size` or fix the query.

## Redis

Live commands target the host from `REDIS_URL`; add `-h HOST -p PORT --tls` as needed. ElastiCache
blocks `CONFIG`; use the `aws elasticache` commands instead.

### RD1. Redis used as a database
- **Check:** data that exists only in Redis (carts, balances, user state) with no rebuild path.
- **Evidence:** `redis-cli CONFIG GET appendonly`. `redis-cli CONFIG GET save`. `redis-cli INFO persistence`.
  Grep writes without TTL: `grep -rniE 'redis.*(::|[.]|->)(set|hset|hmset|lpush|rpush|sadd|zadd)[(]' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor .`
- **Why:** a restart, failover or eviction loses it. Treat Redis as recoverable state.
- **Fix:** move source-of-record data to the DB; if it must stay, AOF `everysec` plus snapshots and a replica.

### RD2. Memory limit and eviction policy
- **Evidence:** `redis-cli CONFIG GET maxmemory`. `redis-cli CONFIG GET maxmemory-policy`. `redis-cli INFO memory`.
  ElastiCache: `aws elasticache describe-cache-parameters --cache-parameter-group-name PARAM_GROUP --query "Parameters[?ParameterName=='maxmemory-policy'].ParameterValue"`.
- **Why:** `noeviction` on a cache returns errors when full; `allkeys-lru` on a queue or session store silently drops jobs and logs users out. Mixing both in one instance makes either choice wrong.
- **Fix:** separate instances (or at least policies) for cache vs queue/sessions; `volatile-lru` when only TTL keys may go.

### RD3. Evictions, hit rate and TTLs
- **Evidence:** `redis-cli INFO stats` (`evicted_keys`, `keyspace_hits`, `keyspace_misses`). `redis-cli INFO keyspace` (`keys` vs `expires`).
- **Why:** high evictions mean undersized; low hit rate means the cache costs more than it saves; keys without TTL grow forever.
- **Fix:** TTL on every cache key; per-concern key prefixes (`cache:`, `sess:`, `rl:`), and strip the framework prefix before raw lookups.

### RD4. Slow and blocking commands
- **Evidence:** `redis-cli SLOWLOG GET 20`. `redis-cli LATENCY DOCTOR`.
  `grep -rnE 'KEYS [*]|redis[a-zA-Z_]*(::|[.]|->)keys[(]|FLUSHALL|FLUSHDB|SMEMBERS|HGETALL' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor .`
- **Why:** Redis is single-threaded; one `KEYS` or huge `HGETALL` stalls every client.
- **Fix:** `SCAN` with `COUNT`, split big keys, `UNLINK` instead of `DEL` for large values.

### RD5. Memory size and fragmentation
- **Evidence:** `redis-cli INFO memory` (`used_memory`, `maxmemory`, `mem_fragmentation_ratio`). `redis-cli MEMORY DOCTOR`.
  `aws elasticache describe-cache-clusters --show-cache-node-info --query 'CacheClusters[].{id:CacheClusterId,type:CacheNodeType,engine:Engine,ver:EngineVersion}'`.
- **Why:** peak `used_memory` under 30% of node memory over weeks is a node class too big; fragmentation above 1.5 wastes RAM.
- **Fix:** one size down; `activedefrag yes`. On ElastiCache, Redis OSS to Valkey keeps the protocol and lists about 20% lower node prices (confirm current pricing).
- **$/mo:** (current node hourly - smaller node hourly) x 730 x nodes; Valkey: node hourly x 0.2 x 730 x nodes.

### RD6. HA, failover and backups (ElastiCache)
- **Evidence:** `aws elasticache describe-replication-groups --query 'ReplicationGroups[].{id:ReplicationGroupId,failover:AutomaticFailover,multiaz:MultiAZ,snap:SnapshotRetentionLimit,tls:TransitEncryptionEnabled,rest:AtRestEncryptionEnabled}'`. `redis-cli INFO replication`.
  Standalone clusters (no replication group, so no failover at all): `aws elasticache describe-cache-clusters --query 'CacheClusters[?ReplicationGroupId==null].{id:CacheClusterId,engine:Engine,nodes:NumCacheNodes,type:CacheNodeType}'`.
- **Why:** a single node holding sessions or queues is a single point of failure.
- **Fix:** a replica with automatic failover for anything not purely cache; TLS and at-rest encryption.

### RD7. Client connections
- **Evidence:** `redis-cli INFO clients` (`connected_clients`, `blocked_clients`). `redis-cli CONFIG GET maxclients`.
- **Why:** per-request connections without pooling exhaust `maxclients` under load.
- **Fix:** shared client per process; rate-limit buckets keyed per (connection, service) so budgets hold across workers.

## DynamoDB

### DY1. Capacity mode vs traffic
- **Evidence:** `aws dynamodb list-tables`. `aws dynamodb describe-table --table-name TABLE --query 'Table.{mode:BillingModeSummary.BillingMode,rcu:ProvisionedThroughput.ReadCapacityUnits,wcu:ProvisionedThroughput.WriteCapacityUnits,bytes:TableSizeBytes,items:ItemCount,class:TableClassSummary.TableClass,protect:DeletionProtectionEnabled}'`.
  `aws cloudwatch get-metric-statistics --namespace AWS/DynamoDB --metric-name ConsumedWriteCapacityUnits --dimensions Name=TableName,Value=TABLE --start-time START_ISO --end-time END_ISO --period 86400 --statistics Sum`, same for `ConsumedReadCapacityUnits`.
  `aws application-autoscaling describe-scalable-targets --service-namespace dynamodb`.
- **Why:** provisioned capacity far above consumption burns money; on-demand for steady high traffic costs more than provisioned with auto scaling.
- **Fix:** steady traffic: provisioned + auto scaling (target 70%); spiky or low: on-demand.
- **$/mo:** provisioned WCU $0.00065/h x 730 = $0.47 per WCU, RCU $0.00013/h x 730 = $0.09; on-demand $0.625 per million writes, $0.125 per million reads. Compare monthly consumed units both ways.

### DY2. Hot partitions and throttling
- **Evidence:** `aws cloudwatch get-metric-statistics --namespace AWS/DynamoDB --metric-name WriteThrottleEvents --dimensions Name=TableName,Value=TABLE --start-time START_ISO --end-time END_ISO --period 3600 --statistics Sum` (and `ReadThrottleEvents`).
  `aws dynamodb describe-contributor-insights --table-name TABLE`.
  Key design in IaC: `grep -rnE 'hash_key|range_key|KeySchema|partitionKey' --include='*.tf' --include='*.ts' --include='*.yml' --include='*.yaml' --include='*.json' --exclude-dir=node_modules --exclude-dir=.git .`
- **Why:** a low-cardinality partition key (status, date, tenant with one giant tenant) caps throughput at one partition no matter the table capacity.
- **Fix:** high-cardinality key, write sharding (`key#0..N`), or a GSI with a better key.

### DY3. Scans in application code
- **Evidence:** `grep -rnE 'ScanCommand|[.]scan[(]|Scan[(]|scan_paginator' --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git .`
- **Why:** a scan reads (and bills) the whole table on every call.
- **Fix:** `Query` on a key or GSI designed for the access pattern.

### DY4. PITR, deletion protection and TTL
- **Evidence:** `aws dynamodb describe-continuous-backups --table-name TABLE`. `aws dynamodb describe-time-to-live --table-name TABLE`. `protect` from DY1.
  IaC: `grep -rnE 'point_in_time_recovery|PointInTimeRecovery|deletion_protection|ttl' --include='*.tf' --include='*.ts' --include='*.yml' --include='*.yaml' --include='*.json' --exclude-dir=node_modules --exclude-dir=.git .`
- **Why:** no PITR means a bad deploy that overwrites items cannot be undone; ephemeral items (sessions, WebSocket connection IDs) without TTL pile up forever.
- **Fix:** enable PITR and deletion protection on source-of-record tables; TTL attribute on ephemeral items.
- **$/mo:** PITR $0.20 per GB-month x table GB.

### DY5. GSI projections and table class
- **Evidence:** `aws dynamodb describe-table --table-name TABLE --query 'Table.GlobalSecondaryIndexes[].{name:IndexName,proj:Projection.ProjectionType,bytes:IndexSizeBytes}'`.
- **Why:** `ALL` projection doubles storage and write cost per GSI. Large, rarely read tables pay Standard storage.
- **Fix:** `KEYS_ONLY` or `INCLUDE`; Standard-IA table class when storage dominates the table's cost.
- **$/mo:** storage GB x ($0.25 Standard - $0.10 Standard-IA); dropped GSI bytes x $0.25 per GB.

### DY6. Private access path
- **Evidence:** `aws ec2 describe-vpc-endpoints --filters Name=service-name,Values=com.amazonaws.REGION.dynamodb`. IaC: `grep -rnE 'aws_vpc_endpoint|dynamodb' --include='*.tf' --exclude-dir=node_modules --exclude-dir=.git .`
- **Why:** from private subnets without the gateway endpoint, DynamoDB traffic goes through the NAT Gateway and is billed per GB.
- **Fix:** add the free gateway endpoint to the private route tables.
- **$/mo:** monthly GB to DynamoDB x $0.045 NAT processing.

### DY7. Tables that look unused
- **Evidence:** zero consumed capacity over 30 days (DY1 metrics).
- **Why:** tables are often read by another repo, a Lambda or an analytics job.
- **Fix:** search every repo and IaC stack for the table name before recommending deletion; back up first. Flag only.
- **$/mo:** table + GSI GB x storage price, plus provisioned units.

## RDS/Aurora

### RDS1. Instance size vs load
- **Evidence:** `aws rds describe-db-instances --query 'DBInstances[].{id:DBInstanceIdentifier,class:DBInstanceClass,engine:Engine,ver:EngineVersion,multiaz:MultiAZ,storage:StorageType,gb:AllocatedStorage,iops:Iops,maxgb:MaxAllocatedStorage,public:PubliclyAccessible,encrypted:StorageEncrypted,backup:BackupRetentionPeriod,protect:DeletionProtection,pi:PerformanceInsightsEnabled}'`.
  `aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name CPUUtilization --dimensions Name=DBInstanceIdentifier,Value=DB_ID --start-time START_ISO --end-time END_ISO --period 86400 --statistics Average Maximum` (also `FreeableMemory`, `DatabaseConnections`).
- **Why:** max CPU under 30% for 14+ days with ample free memory means a class too big. Intel classes cost more than Graviton.
- **Fix:** one size down, or the Graviton class (`db.m6g`/`db.r6g`/`db.t4g`), applied in the maintenance window.
- **$/mo:** (current hourly - target hourly) x 730 x (2 if Multi-AZ).

### RDS2. Multi-AZ where it matters, not where it does not
- **Evidence:** `multiaz` from RDS1; IaC `grep -rnE 'multi_az|MultiAZ|multiAz' --exclude-dir=node_modules --exclude-dir=.git .`
- **Why:** single-AZ production loses writes during an AZ failure; Multi-AZ on dev doubles cost for nothing. After a failover the writer may sit in an AZ the app subnets do not prefer (cross-AZ latency and transfer).
- **Fix:** Multi-AZ on production, off on non-prod; recheck app placement after failovers.
- **$/mo:** non-prod Multi-AZ: instance hourly x 730 saved.

### RDS3. Backups, retention and restore
- **Evidence:** `backup` and `protect` from RDS1. `aws rds describe-db-clusters --query 'DBClusters[].{id:DBClusterIdentifier,engine:Engine,backup:BackupRetentionPeriod,restorable:LatestRestorableTime,protect:DeletionProtection,encrypted:StorageEncrypted}'`.
  `aws rds describe-db-snapshots --snapshot-type manual --query 'DBSnapshots[].{id:DBSnapshotIdentifier,created:SnapshotCreateTime,gb:AllocatedStorage}'`. `aws backup list-backup-plans`.
- **Why:** retention 0 or 1 day, no deletion protection, or no copy outside the account means one mistake loses the data. Old manual snapshots cost money forever.
- **Fix:** retention 7 to 35 days, deletion protection, `skip_final_snapshot = false`, AWS Backup copy to another region or account for production, a scheduled restore test.
- **$/mo:** manual snapshot GB x $0.095 for snapshots past policy.

### RDS4. Exposure and encryption
- **Evidence:** `public` and `encrypted` from RDS1; `grep -rnE 'publicly_accessible|storage_encrypted|PubliclyAccessible|StorageEncrypted' --exclude-dir=node_modules --exclude-dir=.git .`
- **Why:** a publicly reachable DB is one leaked password from a breach; encryption cannot be turned on in place.
- **Fix:** `publicly_accessible = false`, private subnets, SG from app SGs only; encrypted snapshot copy and restore to enable encryption.

### RDS5. Storage type and IOPS
- **Evidence:** `storage`, `iops`, `maxgb` from RDS1. `aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name WriteIOPS --dimensions Name=DBInstanceIdentifier,Value=DB_ID --start-time START_ISO --end-time END_ISO --period 3600 --statistics Maximum` (also `ReadIOPS`).
- **Why:** io1/io2 with provisioned IOPS far above peak use is paid every hour; gp2 small volumes run out of burst credits; no `MaxAllocatedStorage` means a full disk stops the DB.
- **Fix:** gp3 (3,000 IOPS baseline included, 12,000 at 400 GB+ for most engines); enable storage autoscaling.
- **$/mo:** unused provisioned IOPS x $0.10 (io1) per IOPS-month.

### RDS6. Connection limits and RDS Proxy
- **Evidence:** `DatabaseConnections` max from RDS1 vs `max_connections`. `aws rds describe-db-proxies`. Lambda functions touching the DB: `grep -rnE 'aws_lambda_function|Lambda::Function|reserved_concurrent' --exclude-dir=node_modules --exclude-dir=.git .`
- **Why:** Lambda fan-out opens connections per invocation and exhausts `max_connections`.
- **Fix:** RDS Proxy in front, per-function pool of about 5, reserved concurrency on DB-heavy functions.

### RDS7. Aurora Serverless v2 scaling
- **Evidence:** `aws rds describe-db-clusters --query 'DBClusters[].{id:DBClusterIdentifier,min:ServerlessV2ScalingConfiguration.MinCapacity,max:ServerlessV2ScalingConfiguration.MaxCapacity,storage:StorageType}'`.
  `aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name ServerlessDatabaseCapacity --dimensions Name=DBClusterIdentifier,Value=CLUSTER_ID --start-time START_ISO --end-time END_ISO --period 3600 --statistics Average Maximum`.
- **Why:** a high minimum ACU bills idle hours; auto-pause (min 0) resumes in about 10 to 20 s, which fails health checks without a start period; a low max caps throughput in a spike.
- **Fix:** min ACU at the measured idle need (0.5 for irregular traffic), container health check `start_period` above the resume time, max ACU above the observed peak.
- **$/mo:** (current min - new min) ACU x $0.12 x idle hours, e.g. (4 - 0.5) x 0.12 x 500 = $210.

### RDS8. Non-prod running 24/7
- **Evidence:** instance ids/tags with `dev`, `staging`, `test` in RDS1 output; `aws rds describe-db-instances --query 'DBInstances[].{id:DBInstanceIdentifier,tags:TagList}'`.
- **Why:** non-prod used 50 hours a week is billed for 168.
- **Fix:** stop on a schedule (RDS restarts stopped instances after 7 days, so the schedule must re-stop), and downsize.
- **$/mo:** hourly x (730 - about 220 working hours).

### RDS9. Engine version and Extended Support
- **Evidence:** `engine`/`ver` from RDS1. `aws rds describe-db-engine-versions --engine postgres --engine-version VERSION --query 'DBEngineVersions[].{ver:EngineVersion,status:Status}'`. `aws rds describe-pending-maintenance-actions`.
- **Why:** majors past standard support are charged RDS Extended Support per vCPU-hour and miss fixes.
- **Fix:** upgrade the major with a blue/green deployment after testing on a restored snapshot.
- **$/mo:** vCPUs x Extended Support rate x 730, e.g. 4 x $0.10 x 730 = $292 (year 1 to 2 rate; confirm for the engine).

### RDS10. Reserved capacity
- **Evidence:** `aws rds describe-reserved-db-instances`. Steady production instances from RDS1.
- **Why:** steady 24/7 production on on-demand pays well over a 1-year reservation.
- **Fix:** 1-year no-upfront reservation for production after rightsizing (RDS1) first.
- **$/mo:** on-demand monthly - reserved effective monthly from the AWS pricing page.

### RDS11. Observability and parameters
- **Evidence:** `pi` from RDS1. `aws rds describe-db-instances --query 'DBInstances[].{id:DBInstanceIdentifier,logs:EnabledCloudwatchLogsExports,pg:DBParameterGroups[].DBParameterGroupName}'`. `aws rds describe-db-parameters --db-parameter-group-name PARAM_GROUP --source user`.
- **Why:** without query-level insight and slow-query logs, nobody can see which query hurts; the default parameter group cannot be changed when you need to.
- **Fix:** custom parameter group with `log_min_duration_statement = 1000` and `rds.force_ssl = 1` (Postgres), or `slow_query_log = 1` and `require_secure_transport = ON` (MySQL); Performance Insights or CloudWatch Database Insights, which is replacing it (check current retention and pricing).

### RDS12. Aurora I/O cost
- **Evidence:** `storage` from RDS7 (`aurora` vs `aurora-iopt1`). `aws ce get-cost-and-usage --time-period Start=START_DATE,End=END_DATE --granularity MONTHLY --metrics UnblendedCost --group-by Type=DIMENSION,Key=USAGE_TYPE --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Relational Database Service"]}}'`.
  Each Cost Explorer API call costs $0.01: run it once, not per cluster.
- **Why:** when I/O charges exceed about 25% of the Aurora bill, I/O-Optimized is cheaper.
- **Fix:** switch the cluster storage type to I/O-Optimized (command for the human).
- **$/mo:** I/O charges - (I/O-Optimized instance and storage uplift).

### RDS13. Alarms and replica lag
- **Evidence:** `aws cloudwatch describe-alarms --query "MetricAlarms[?Namespace=='AWS/RDS'].{name:AlarmName,metric:MetricName,threshold:Threshold,actions:AlarmActions}"`.
  `aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name ReplicaLag --dimensions Name=DBInstanceIdentifier,Value=DB_ID --start-time START_ISO --end-time END_ISO --period 3600 --statistics Maximum` (Aurora: `AuroraReplicaLag`).
- **Why:** with no `FreeStorageSpace` alarm, the first signal of a full disk is the outage; no alarm on `CPUUtilization`, `DatabaseConnections` or `ReplicaLag` means users report the problem first. An alarm with no action notifies nobody.
- **Fix:** alarms with an SNS action on `FreeStorageSpace` (under 10% of allocated), `CPUUtilization`, `DatabaseConnections` (over 80% of `max_connections`), `ReplicaLag`, and `FreeableMemory`.
- **$/mo:** $0.10 per standard alarm.

## SQLite

### SQ1. Database on ephemeral disk
- **Evidence:** `grep -rnE 'DB_CONNECTION=sqlite|sqlite:|[.]sqlite|database.sqlite' --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git .` plus the deploy target (container without a volume).
- **Why:** a container filesystem is wiped on each deploy; the data goes with it.
- **Fix:** mount a volume, or move to a managed DB for anything stateful.

### SQ2. Journal mode and integrity
- **Evidence:** `sqlite3 -readonly app.db "pragma journal_mode"`. `sqlite3 -readonly app.db "pragma integrity_check"`.
- **Why:** rollback journal mode blocks readers during writes; corruption goes unnoticed until restore.
- **Fix:** `journal_mode=WAL` and `busy_timeout` set by the app; backups via `.backup` or Litestream.

## Migrations (any engine)

Read the migration files; size each touched table with PG13 or MY7. "Big" means about 1M+ rows
or 1 GB+, or any table on a hot request path.

### MIG1. Locking or rewriting ALTERs
- **Evidence:** `grep -rniE 'alter table|alter column|change_column|->change|AlterField|alter_column|set not null|add constraint|foreign key|add_foreign_key|->foreign[(]|foreignId|constrained' database/migrations db/migrate migrations prisma alembic drizzle`
- **Why:** Postgres: `ALTER COLUMN TYPE`, `ADD COLUMN` with a volatile default (or any default before PG11), and `SET NOT NULL` take `ACCESS EXCLUSIVE` and rewrite or scan the table; an FK or CHECK added without `NOT VALID` scans under lock. Even a fast ALTER queues behind a long transaction and blocks every query behind it. MySQL: a `COPY` algorithm ALTER blocks writes for the whole copy.
- **Fix:** `set lock_timeout = '5s'` in the migration and retry; FK/CHECK as `NOT VALID` then `VALIDATE CONSTRAINT` separately; `SET NOT NULL` via a validated `CHECK (col is not null)` first (PG12+); MySQL `ALGORITHM=INSTANT` or `INPLACE, LOCK=NONE`, or gh-ost/pt-online-schema-change for big tables.

### MIG2. Non-concurrent index builds
- **Evidence:** `grep -rniE 'create (unique )?index|add_index|->index[(]|->unique[(]|AddIndex|models[.]Index|create_index|@@index|@@unique' database/migrations db/migrate migrations prisma alembic drizzle`, then check for `concurrently` and for the transaction opt-out.
- **Why:** Postgres `CREATE INDEX` without `CONCURRENTLY` blocks writes for the whole build. `CONCURRENTLY` cannot run inside a transaction, so the migration must opt out.
- **Fix:** `create index concurrently` with the framework's opt-out: Rails `disable_ddl_transaction!` + `algorithm: :concurrently`, Django `AddIndexConcurrently` with `atomic = False`, Laravel `$withinTransaction = false` + raw statement, Alembic `postgresql_concurrently=True` in an autocommit block, Prisma: hand-edit the SQL. MySQL: `ALGORITHM=INPLACE, LOCK=NONE`. Check for an `INVALID` index after a failed concurrent build.

### MIG3. Backfills in the schema migration
- **Evidence:** `grep -rniE 'update |->update|update_all|RunPython|bulk_update|execute' database/migrations db/migrate migrations alembic`
- **Why:** one transaction updating millions of rows holds locks, bloats the table, can fill the WAL/binlog, and rolls the whole thing back on timeout.
- **Fix:** schema change first; backfill in a separate, idempotent job in batches of 1k to 10k rows with a pause; then add the constraint.

### MIG4. NOT NULL without a default on big tables
- **Evidence:** `grep -rniE 'not null|nullable[(]false[)]|null: false|null=False' database/migrations db/migrate migrations prisma alembic drizzle`
- **Why:** fails outright on a non-empty table, or forces a rewrite/scan under lock.
- **Fix:** add nullable, backfill (MIG3), then add a validated CHECK and `SET NOT NULL`; or a constant default (metadata-only on PG11+ and MySQL 8 `INSTANT`).

### MIG5. Destructive and renaming changes
- **Evidence:** `grep -rniE 'drop table|drop column|truncate|rename|dropColumn|remove_column|RemoveField|RenameField' database/migrations db/migrate migrations prisma alembic drizzle`
- **Why:** old app instances still running during a deploy break on renamed or dropped columns; a blind revert of a destructive migration in an incident loses more data.
- **Fix:** expand/contract over separate deploys (add, dual-write, backfill, switch reads, drop later). Classify every migration as safe, caution or destructive and state the rollback path in the PR. In recovery, deploy a schema-compatible app version instead of reverting.

### MIG6. More than one service runs migrations
- **Evidence:** `grep -rnE 'migrate|db:push|prisma migrate|alembic upgrade|knex migrate' --include='Dockerfile*' --include=Procfile --include='railway.*' --include='docker-compose*' --include=fly.toml --include=package.json --exclude-dir=node_modules --exclude-dir=.git .`
- **Why:** two services migrating on boot without a lock race and half-apply; services that restart later run old code against the new schema.
- **Fix:** one migrator (the API's pre-deploy step), auto-migrate off everywhere else, expand/contract migrations.

### MIG7. Schema sync on production
- **Evidence:** `grep -rnE 'db push|drizzle-kit push|ddl-auto=update|ddl-auto: update|sync[(][{] *alter|synchronize: true' --exclude-dir=node_modules --exclude-dir=.git .`
- **Why:** schema sync can drop or rewrite columns with no reviewable migration and no rollback.
- **Fix:** generated, checked-in migrations reviewed like code.

### MIG8. Down migrations and parallel branches
- **Evidence:** migrations with an empty or missing `down`; the same column added or changed in two recent migrations (`grep -rnE 'COLUMN_NAME' database/migrations db/migrate migrations`).
- **Why:** a `down()` that only fails on the production engine leaves no rollback; parallel branches adding the same intent (or fixing precision twice) leave drift.
- **Fix:** test `down` on the production engine in CI; decide numeric precision up front; rebase schema PRs and recheck.

### MIG9. Production data fixes
- **Evidence:** data-changing SQL in migrations or scripts run against production.
- **Why:** a fix with no rollback copy cannot be undone.
- **Fix:** lock the rows, assert the exact preconditions and abort on mismatch, copy original columns to a rollback table in the same DB, one transaction, verify with a fresh read. Never retry a failed migration or delete data during an incident without an owner decision.
