# Performance checklist

Each item: **Check**, **Evidence** (Grep = code search with the agent's search tool; Run =
read-only command that passes the guard, only after consent), **Costs because**, **Fix**.
Placeholders are UPPERCASE. Replace them with literal values before running.

Run each `Run:` command once, never in a loop. Prefer a read replica when one exists.

## 1. N+1 queries and per-request query count

- **Check**: loops that query per item, lazy-loaded relations in lists, serializers or
  templates that touch relations, GraphQL resolvers without a loader, `count()` per row.
- **Evidence**: Grep by ORM, then read the loop:
  - Laravel: `foreach` bodies using `->` relation access, `->load(`, `->count()`, missing
    `with(`; resources that read `$this->relation`.
  - Django: `\.objects\.(get|filter)\(` inside a `for`, templates reading `obj.related.field`,
    serializers with nested fields and no `select_related`/`prefetch_related`.
  - Rails: `.each` over a relation that calls an association, missing `includes(`/`preload(`,
    `.count` or `.exists?` inside a loop.
  - Node: `findUnique`/`findOne`/`findByPk`/`getRepository` inside `map`/`for`, `Promise.all`
    over per-item queries, missing Prisma `include`, TypeORM `relations`, Sequelize `include`,
    Drizzle `with`.
  - Run (PostgreSQL 13+): `psql -c 'select calls, round(mean_exec_time) as ms, substring(query, 1, 80) as q from pg_stat_statements order by calls desc limit 20'`
  - Run (PostgreSQL 12 and older): `psql -c 'select calls, round(mean_time) as ms, substring(query, 1, 80) as q from pg_stat_statements order by calls desc limit 20'`
  - Run: `mysql -e 'select digest_text, count_star from performance_schema.events_statements_summary_by_digest order by count_star desc limit 20'`
- **Costs because**: queries per request grow with page size. 50 rows x 3 relations + 1 = 151
  queries; at 2 ms each that is about 300 ms of database time per request.
- **Fix**: eager-load, batch with `IN`, add a loader, or paginate. Turn on lazy-load detection
  (item 10).

## 2. Unbounded queries and missing pagination

- **Check**: list endpoints and pages that return every row, `all()` or `find()` with no limit,
  search with no cap, exports built in the request.
- **Evidence**: Grep `::all\(\)`, `->get\(\)`, `\.all\(\)`, `\.objects\.all`, `findMany\(\)`,
  `find\(\{\}\)`, `SELECT \*` with no `LIMIT`; routes that take no `page` or `limit`.
- **Costs because**: rows x bytes per row per request. 20,000 rows x 1 KB = 20 MB and a full
  table read on every hit, growing with the table.
- **Fix**: paginate (cursor for big tables), cap `limit`, select only needed columns, move
  exports to a queued job.

## 3. Slow work in the request path

- **Check**: mail, outbound HTTP, webhooks, file or image processing, PDF generation and
  report builds done before the response is sent.
- **Evidence**: Grep `Mail::send`, `send_mail`, `deliver_now`, `nodemailer`, `sendMail`,
  `Http::`, `requests\.(get|post)`, `axios`, `fetch\(`, `Net::HTTP`, `intervention`, `sharp`,
  `Pillow`, `ImageMagick`, `dompdf`, `wkhtmltopdf` in controllers and views.
- **Costs because**: the user waits for it. A 600 ms mail API call adds 600 ms to every
  signup, and a slow provider blocks the worker for the whole call.
- **Fix**: dispatch to a queue (`dispatch`, `.delay`, `deliver_later`, a job runner) and return
  at once. Resize images on upload, once, not on read.

## 4. Outbound calls with no timeout

- **Check**: every HTTP, DB and cache client has a connect and a read timeout.
- **Evidence**: Grep the client calls from item 3. Look for a missing `timeout`, `Http::timeout`,
  `requests` without `timeout=`, `Net::HTTP` `read_timeout`, `AbortSignal.timeout`, axios
  `timeout`. Most clients default to no timeout or minutes.
- **Costs because**: one hung upstream holds a worker until the platform kills it. With 8
  workers and one stuck dependency, 8 requests stop the whole app.
- **Fix**: set connect 1 to 3 s and read 5 to 10 s, retry only idempotent calls, and fail fast
  with a clear error.

## 5. Hot reads with no cache

- **Check**: the same expensive read repeated on every request: settings, menus, counts,
  rendered fragments, third-party responses.
- **Evidence**: Grep the hot controllers for queries on data that rarely changes. Check for
  `Cache::`, `cache.get`, `@cache`, `Rails.cache`, `redis`, HTTP `Cache-Control`. Run
  (consented, PostgreSQL): the item 1 statistics show the same query with a high `calls`.
- **Costs because**: 200 req/s x one 5 ms query = 1 s of database time per second for one
  value that changed once this week.
- **Fix**: cache with a TTL and clear it on write. Guard against stampede: lock or
  stale-while-revalidate on the cache miss, and jitter the TTLs so keys do not expire together.

## 6. Whole tables or files in memory

- **Check**: loops that load every row or read a whole file into memory.
- **Evidence**: Grep `->get\(\)` then `foreach`, `\.all\(\)` then iterate, `file_get_contents`,
  `readFileSync`, `\.read\(\)`, `fetchAll`, `toArray\(\)`, `Buffer.concat`.
- **Costs because**: memory = rows x bytes per row. 1 million rows x 500 B = 500 MB, which
  exceeds a 512 MB container and ends in an out-of-memory kill.
- **Fix**: stream or batch: `chunk`/`cursor`/`lazy()`, `iterator()`, `find_each`, `for await`
  over a stream. Stream file downloads and uploads.

## 7. Oversized responses and payload size

- **Check**: serializers that return every column or nested relation, no field selection, and
  no response compression.
- **Evidence**: Grep API resources and serializers (`toArray`, `JsonResource`, `serializers.`,
  `as_json`, `to_json`, `res.json(` of a whole model). Check config for `gzip`, `brotli`,
  `compression(`, `GZipMiddleware`, `Rack::Deflater`, or a CDN doing it.
  - Run (only a URL the user named, one request): `curl -sI -H 'Accept-Encoding: gzip' URL`
- **Costs because**: bytes = rows x fields x size. 100 rows x 2 KB = 200 KB per call; gzip
  often cuts JSON by 70 to 80 percent, so skipping it sends about 5x the bytes.
- **Fix**: return only the fields the client uses, paginate, enable gzip or brotli at the app
  or the edge.

## 8. Frontend bundle size

- **Check**: large JS and CSS, no code splitting, big libraries for small jobs, source maps or
  dev builds served, no tree-shaking.
- **Evidence**: read `package.json` dependencies and the build config (`vite.config.*`,
  `webpack.config.*`, `next.config.*`). Grep for whole-library imports (`import _ from 'lodash'`,
  `import moment`), missing `React.lazy`/dynamic `import(`. If a build output exists, list sizes:
  - Run: `ls -lS public/build/assets`
  - Run: `du -sh public/build dist build .next`
- **Costs because**: bytes over the wire. A 1.2 MB bundle on a 1.6 Mbps phone link is about
  6 s before the page runs (1.2 MB x 8 / 1.6 Mbps).
- **Fix**: split by route, lazy-load heavy components, replace large libraries with small ones,
  turn on minification and tree-shaking, set long-cache headers on hashed files.

## 9. Unoptimised images

- **Check**: large originals served to small slots, no modern formats, no lazy loading, no
  width and height.
- **Evidence**: Grep `<img` and `Image` usage for `loading="lazy"`, `srcset`, `width`. Find big
  files in `public/`, `static/`, `assets/`:
  - Run: `find public -type f -size +300k`
- **Costs because**: bytes. Six 2 MB JPEGs on a page = 12 MB; WebP or AVIF at the right size is
  often 80 to 90 percent smaller.
- **Fix**: resize to the display size, serve WebP or AVIF with `srcset`, lazy-load below the
  fold, and put images behind a CDN.

## 10. Turn on lazy-load detection

- **Check**: the stack can fail or warn on lazy loading in dev and test, so N+1s are caught
  before production.
- **Evidence**: Grep for the switch:
  - Laravel: `Model::preventLazyLoading` (and `shouldBeStrict`) in `AppServiceProvider`.
  - Django: `nplusone` or `django-debug-toolbar` in requirements and settings.
  - Rails: `strict_loading` on models or `config.active_record.strict_loading_by_default`,
    or the `bullet` gem in the Gemfile.
  - Node: Prisma query logging (`log: ['query']`) or a loader library; no built-in switch.
- **Costs because**: without it, every new relation access in a loop is a silent regression.
- **Fix**: enable it outside production and fix what it raises. List the one-line change
  under "Commands for you to run".
