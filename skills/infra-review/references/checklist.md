# infra-review checklist

Work through General first, then only the platform sections the repo uses. Each item gives:
what to check, the evidence (a repo pattern and/or a read-only command), why it matters, the
typical fix, and an est. $/mo where one exists. Prices are list prices for a common region;
confirm against the user's region before quoting, and show the arithmetic in the report.

Every command below is one CLI call, optionally piped into a filter, and passes the read-only
guard. Replace UPPERCASE placeholders with the user's own values. Commands the guard blocks
(writes, `beta`/`alpha` CLI paths, unlisted verbs) go in the report's "Commands for you to run".

For AWS cost, security and performance depth, hand off to `aws-billing-review`,
`aws-security-review` and `aws-bottleneck-review`. This checklist covers how the AWS stack
is deployed, recovered and watched.

Never print secret values (contract section 6): list variable NAMES only, use `grep -l`/`-c`
for secret patterns, and never open `.env*`, `*.tfstate*`, kubeconfigs or credential files.

## General

### Deploy and rollback

- **Merged is not deployed.** Check that every service runs the merge commit. Evidence: a
  `/version` or health route returning the commit; `curl -s https://example.com/version` vs
  `git rev-parse HEAD`; `gh run list --branch main --limit 10`. Why: dropped webhooks, paused
  deploys and unconnected sources leave merges undeployed for weeks with green CI. Fix: expose the
  deployed SHA and compare it after every merge, per service. Est.: n/a.
- **CI deploys the exact SHA after tests.** Evidence: platform autodeploy on push;
  `.github/workflows/*.yml` deploy jobs without `needs:` on tests. Why: "wait for CI" gates can
  pass when one workflow was cancelled and another succeeded. Fix: disable native autodeploy,
  deploy the tested SHA from CI once, retry only reads, poll for a new deployment with that SHA.
- **A tested rollback path exists.** Evidence: runbooks in `docs/`, deploy scripts, images tagged by
  commit (not `latest`). Why: without a known-good artifact, rollback is a rebuild under pressure.
  Fix: tag images by commit, keep the last N, write the rollback command into the runbook.
- **Migrations are safe for rollback.** Evidence: migrations dropping or renaming columns in the
  release that stops using them; `migrate` in a Dockerfile `CMD` or entrypoint. Why: blue/green and
  rollback share one DB, and every replica races to migrate at boot. Fix: expand/contract across
  releases; migrate once in a pre-deploy/release phase; workers wait for migrations.
- **Health checks fail closed.** Evidence: deploy scripts that log and continue on a failed check;
  a static `health.html`; checks accepting 3xx. Why: a static file reports up while the app or DB
  is down. Fix: liveness plus a readiness route that touches the DB with short timeouts; abort and
  keep the old version on failure; web readiness independent of scheduler freshness.
- **Deploys do not kill in-flight work or double-run singletons.** Evidence: drain/stop grace
  (`stop_grace_period`, `terminationGracePeriodSeconds`), scheduler replica counts and overlap.
  Why: a 0 s drain SIGKILLs jobs; overlapping schedulers double-send. Fix: grace above the longest
  job, a sweeper for stuck rows, one scheduler replica with zero overlap and an advisory lock.

### Backups, restore and DR

- **Backups exist, are off the box, and a restore was tested.** Evidence: backup config in IaC
  (retention, PITR), backup jobs, a dated restore drill in `docs/`, written RPO/RTO. Why: an
  untested backup is a guess; a backup in the same host or account dies with it. Fix: automated
  backups, a copy in another region/account/provider, a quarterly restore into an isolated
  environment (never the live service). Est.: for example 50 GB x $0.095 = $4.75/mo RDS snapshots.
- **Local disk is not the system of record.** Evidence: `*.sqlite`, `uploads/`, JSON data files,
  `SESSION_DRIVER=file` on container disk. Why: container disk is wiped on deploy. Fix: managed
  DB or object storage, or a volume plus backups. Est.: n/a.

### Observability and alerting

- **Alerts reach a human.** Evidence: alarms/alert policies in IaC with a notification target.
  Fix: alert on readiness, 5xx rate, disk, memory and backup failures, routed to a pager or chat.
  Est.: for example 10 x $0.10 = $1/mo on CloudWatch.
- **Monitoring runs outside the monitored platform.** Why: a platform outage or spend limit also
  takes down its own alerting; email cannot report its own failure; GitHub Actions cron can run
  hours late. Fix: an external probe with a short deadline, redirects as failures, alert on first
  failure, and a delivery drill. Est.: often $0.
- **Schedulers prove they ran.** Fix: a heartbeat written after tasks succeed, alert on staleness;
  a queue probe kept out of the deploy health check. Auto-recovery restarts only the diagnosed
  service and never auto-rolls back an image or touches the DB.
- **Logs are retained and sized.** Evidence: DEBUG level in prod, no retention. Fix: INFO, 14 to 30
  day retention. Est.: for example 20 GB x $0.50 = $10/mo CloudWatch Logs ingest.

### Single points of failure

- **One box, one zone, one region.** Evidence: app and DB on one instance, single-AZ DB, one web
  replica. Fix: separate DB, HA DB where RTO demands it, two web replicas behind a load balancer.
  Est.: HA usually doubles the DB instance line; state it as the price of the RTO.
- **Clocks are synced.** Why: skew of minutes breaks short-lived signed tokens. Fix: NTP/chrony.

### Secrets handling

- **No secrets in the repo, images or build args.** Evidence: `git ls-files` for `.env` files;
  `grep -rlE 'AKIA|sk_live_|BEGIN .*PRIVATE KEY' .` (file names only); `ENV`/`ARG` keys in
  Dockerfiles; secrets in `NEXT_PUBLIC_*`/`VITE_*`; committed HAR files or recordings. Why: public
  build vars are inlined into client bundles. Fix: platform secret store at runtime; anchored
  `.gitignore` paths (`/app/`, not `app/`). Est.: n/a.
- **Variable names match code.** Why: drifted names break features silently. Fix: fail boot on
  missing required variables; a CI job boots the image with no variables and asserts it names
  the missing one. Est.: n/a.

### Caching and edge data

- **A database-backed cache does not hold large blobs.** Evidence: `CACHE_STORE=database` (or
  equivalent) caching rendered HTML or full payloads. Why: every hit reads and deserializes a fat
  row from the primary DB, which made a cached page slower than an uncached one. Fix: cache
  metadata only and hydrate content on demand, or move the cache to Redis/memory. Est.: n/a.
- **Use geo data from an edge header before paying for GeoIP.** Evidence: a GeoIP database
  download, a paid IP-geo API, or a predeploy step fetching a GeoIP file. Why: CDNs such as
  Cloudflare already resolve country at the edge for free (`Cf-Ipcountry`). Fix: read the edge
  header, and trust it only when the origin is reachable through the CDN alone. Est.: the GeoIP
  subscription saved.

### CI pipeline safety

- **Least-privilege workflows.** Evidence: `permissions:` missing or `write-all`; actions pinned by
  tag. Fix: `permissions: contents: read`, third-party actions pinned to SHAs, OIDC instead of
  stored cloud keys, placeholder account IDs in committed ARNs.
- **Required checks are required.** Evidence: `gh api repos/OWNER/REPO/branches/main/protection`.
  Why: an aggregate checks job does nothing until branch protection requires it. Keep main-branch
  checks; the merged tree can differ from the PR.
- **Releases are serialized and versions match.** Fix: a concurrency group with
  `cancel-in-progress: false` for production; refuse tags that differ from manifest versions.
- **Minutes are bounded.** Evidence: no `timeout-minutes`, no docs `paths-ignore`, duplicate push
  and pull_request runs. Why: an exhausted limit looks like jobs that never start. Est.: for
  example 3,000 min x $0.008 = $24/mo on Linux runners.

## AWS

- **Terraform state is remote and locked.** Evidence: no `backend` block, or an S3 backend without
  locking. Why: local state is lost or overwritten by two applies. Fix: S3 backend with versioning
  and lockfile/DynamoDB locking; reconcile state after any out-of-band deletion. Validate config
  with `terraform init -backend=false` then `terraform validate`. Est.: under $1/mo.
- **Subnets actually route.** Evidence: `aws_subnet` with no `aws_route_table_association`, public
  IPs on subnets with no internet gateway route; `aws ec2 describe-route-tables --query 'RouteTables[].[RouteTableId,Associations[].SubnetId,Routes[].GatewayId]' --output json`.
  Why: instances get a public IP and no way out. Fix: associate route tables explicitly. Est.: n/a.
- **AMIs are pinned.** Evidence: `data "aws_ami"` with `most_recent = true` feeding `aws_instance.ami`.
  Why: a later apply replaces the instance when a new image ships. Fix: pin the AMI ID or
  `lifecycle { ignore_changes = [ami] }`; bake runtimes into images instead of `user_data` installs.
  Check Graviton (arm64) AMI availability before picking a family. Est.: n/a.
- **Single-instance app and DB.** Evidence: one `aws_instance` running both; `aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,MultiAZ,BackupRetentionPeriod,DeletionProtection]' --output table`.
  Fix: managed DB, Multi-AZ where RTO needs it, retention of 7+ days, deletion protection on.
  Est.: Multi-AZ doubles the instance line, for example 2 x $70 = $140/mo for a small instance.
- **Backups are centralized and copied.** Evidence: `aws backup list-backup-plans`;
  `aws backup list-protected-resources --query 'Results[].ResourceArn' --output json`. Fix: AWS Backup
  plan with a cross-region or cross-account copy for the production DB and volumes. Est.: for
  example 100 GB x $0.05 = $5/mo warm storage plus copy transfer.
- **Rollback is automatic where it can be.** Evidence: Lambda deploy config, ECS
  `deployment_circuit_breaker`, CodeDeploy groups; `aws ecs describe-services --cluster CLUSTER --services SERVICE --query 'services[].deploymentConfiguration'`.
  Fix: Lambda canary (`LambdaCanary10Percent5Minutes`) with an Errors alarm on the alias; ECS
  circuit breaker with `rollback = true`. Est.: n/a.
- **Alarms have subscribers.** Evidence: `aws cloudwatch describe-alarms --query 'MetricAlarms[].[AlarmName,StateValue,AlarmActions]' --output json`;
  `aws sns list-subscriptions --query 'Subscriptions[].[TopicArn,Protocol]' --output table`. Why: an
  alarm with no action or an unconfirmed subscription alerts nobody. Est.: $0.10 per alarm/mo.
- **The origin is not reachable around CloudFront/WAF.** Evidence: ALB security group ingress from
  `0.0.0.0/0` while CloudFront fronts it; `aws ec2 describe-security-groups --query 'SecurityGroups[].[GroupId,IpPermissions[].IpRanges[].CidrIp]' --output json`.
  Why: direct hits skip WAF and spoof any CDN-only header. Fix: allow only the CloudFront managed
  prefix list, plus a secret origin header checked at the ALB. Depth: `aws-security-review`. Est.: n/a.
- **External health checks exist.** Evidence: `aws route53 list-health-checks --query 'HealthChecks[].HealthCheckConfig.FullyQualifiedDomainName'`.
  Est.: $0.75/mo per non-AWS endpoint.
- **Secrets come from SSM or Secrets Manager.** Evidence: keys in `user_data`, task definition
  `environment` (not `secrets`), Lambda env vars. Depth: `aws-security-review`. Est.: $0.40 per
  secret/mo in Secrets Manager; SSM standard parameters are free.

## GCP

- **Cloud Run rollback and traffic.** Evidence: `gcloud run revisions list --service=SERVICE --region=REGION`;
  `gcloud run services describe SERVICE --region=REGION --format=json | jq '.status.traffic'`
  (always project with jq: the full describe prints env values). Why:
  revisions are the rollback path; deploying with `--no-traffic` plus a gradual shift is the canary.
  Fix: tag revisions by commit, document the traffic-shift rollback. Est.: n/a.
- **The run.app URL does not bypass the load balancer.** Evidence: `gcloud run services list --format='table(metadata.name,metadata.annotations.run.googleapis.com/ingress)'`.
  Why: with ingress `all`, the default `*.run.app` URL skips Cloud Armor and any CDN, and any header
  trust set at the edge. Fix: ingress `internal-and-cloud-load-balancing`, or disable the default
  URL. Est.: n/a.
- **Cloud Run disk is memory.** Writes count against memory, vanish with the instance and are not
  shared. Fix: Cloud Storage or a mounted volume. Est.: n/a.
- **Cloud SQL is HA and backed up.** Evidence: `gcloud sql instances list --format='table(name,settings.availabilityType,settings.backupConfiguration.enabled,settings.backupConfiguration.pointInTimeRecoveryEnabled)'`;
  `gcloud sql backups list --instance=INSTANCE`. Fix: `availability_type = "REGIONAL"` where RTO
  needs it, backups and PITR on, `deletion_protection = true`. Est.: REGIONAL roughly doubles the
  instance line; backups about $0.08/GB-mo.
- **GKE is regional.** Evidence: `gcloud container clusters list --format='table(name,location,currentNodeCount)'`;
  `kubectl get pdb -A`. Why: a zonal cluster's control plane is one zone. Fix: regional cluster,
  PodDisruptionBudgets, at least two replicas for web. Est.: regional control plane fee per cluster.
- **Terraform state in a versioned bucket.** Evidence: `backend "gcs"`; `gcloud storage buckets describe gs://BUCKET --format='json(versioning)'`.
- **Alert policies have channels.** Evidence: `google_monitoring_alert_policy` with
  `notification_channels` in IaC. The CLI path is beta, so list it under "Commands for you to run":
  `gcloud beta monitoring policies list`. Est.: n/a.
- **Service accounts are not Editor.** Evidence: `gcloud projects get-iam-policy PROJECT_ID --format=json | jq '.bindings[] | select(.role == "roles/editor")'`.
  Why: the default compute service account with Editor turns any compromised workload into project
  admin. Fix: a dedicated least-privilege account per service. Est.: n/a.
- **Secrets in Secret Manager, not env.** Evidence: `gcloud secrets list` (names only); `env`
  entries in `service.yaml`/`app.yaml` that hold literal secrets (report the key, not the value). Est.: about $0.06 per secret version/mo.
- **Log retention and sinks.** Evidence: `gcloud logging sinks list`. Fix: retention matched to need;
  exclude DEBUG logs. Est.: ingestion past the free allotment at $0.50/GiB.

## Azure

- **App Service has a slot to swap back to.** Evidence: `az resource list --resource-type Microsoft.Web/sites/slots -o table`.
  Why: slot swap is the fast rollback and warm-up path. Fix: deploy to a staging slot, swap, keep
  the old build there. Est.: needs Standard tier or higher.
- **The azurewebsites.net host does not bypass Front Door.** Evidence: `az webapp config show --name APP -g RG --query 'ipSecurityRestrictions'`;
  `az resource list --resource-type Microsoft.Cdn/profiles -o table`. Why: the default host skips WAF
  and header trust set at the edge. Fix: access restriction to the `AzureFrontDoor.Backend` service
  tag plus an `X-Azure-FDID` header check. Est.: n/a.
- **Local disk assumptions.** App Service `/home` persists; container local storage and Container
  Apps replicas do not share or keep files. Fix: Blob storage or Azure Files. Est.: n/a.
- **Databases are zone-redundant and geo-backed-up.** Evidence: `az postgres flexible-server list -o table`;
  `az sql db list --server SERVER -g RG -o table`; IaC `geo_redundant_backup_enabled`,
  `high_availability`, `zone_redundant`. Fix: HA where RTO needs it, geo-redundant backups,
  retention 7+ days. Est.: zone-redundant HA roughly doubles compute.
- **VM backups exist.** Evidence: `az resource list --resource-type Microsoft.RecoveryServices/vaults -o table`;
  `az vm list -d -o table`. Why: a single VM with no vault is a one-disk business. Fix: Recovery
  Services vault with a backup policy, availability zones or a scale set for web. Est.: per
  protected instance plus storage.
- **Resource locks on production data.** Evidence: `az lock list -o table`. Fix: `CanNotDelete` on
  the production DB, storage and vault. Est.: $0.
- **Alerts have action groups.** Evidence: `az resource list --resource-type Microsoft.Insights/metricAlerts -o table`;
  `az resource list --resource-type Microsoft.Insights/actionGroups -o table`. Est.: about $0.10 per
  metric alert/mo.
- **Secrets via Key Vault references and managed identity.** Evidence: `az keyvault list -o table`;
  plain secrets in app settings or ARM/Bicep parameters. Est.: about $0.03 per 10,000 operations.
- **Log Analytics retention.** Evidence: `az monitor log-analytics workspace list -o table`. Est.:
  ingestion GB x list price per GB; DEBUG logs inflate it.

## Railway

### Checks

- **Pre-deploy writes do not reach runtime.** `preDeployCommand` runs in a separate ephemeral
  container; files it writes (a downloaded DB, generated config) never reach the serving container
  unless a volume is attached. Evidence: `railway.json`/`railway.toml` `preDeployCommand` that
  downloads or writes files. Fix: do the work at boot or in the image, or attach a volume. Run
  migrations in pre-deploy (once, before replicas start), not in `CMD`. Est.: n/a.
- **Separate services share no volume.** A volume attaches to one service only, so web and
  scheduler/worker share no files. Evidence: jobs on one service reading files another service
  writes; SQLite or JSON files outside a mount path (wiped on every deploy). Fix: run those jobs
  on the service that owns the volume, or use object storage; volumes mount as root, so chown in an
  entrypoint. Est.: volume about $0.15/GB-mo.
- **The generated domain is removed when a CDN fronts the app.** A platform-generated origin domain
  (`*.up.railway.app`) bypasses the CDN/WAF and breaks any trust in CDN-only headers
  (`Cf-Ipcountry`, `Cf-Connecting-Ip`). Evidence: code reading CDN headers plus a generated domain
  still attached (`railway status --json`). Fix: remove the generated domain in the dashboard
  (service, Settings, Networking). Est.: n/a.
- **Only web/API migrates.** Evidence: several services sharing one config file with
  `preDeployCommand` and `healthcheckPath`. Fix: clear both on workers and schedulers with an empty
  list (a `null` is silently ignored) and read it back; gate workers on a wait-for-migrations step
  that exits non-zero after a timeout. Est.: n/a.
- **Draining, overlap and restart policy.** Default draining is 0 s and old/new containers
  overlap. Fix: draining above the longest job; overlap 0 and one replica for schedulers plus an
  advisory lock; restart ALWAYS for workers and schedulers, ON_FAILURE with bounded retries for
  web; health check a cheap liveness route with a generous startup timeout. Est.: n/a.
- **Hard compute limit has headroom.** Why: hitting it stops every service at once (web, workers,
  Postgres, Redis); the usage email is only a warning. Fix: set the limit above peak; on
  simultaneous failures check usage before code. Est.: compute about $20/vCPU-mo, $10/GB-mo RAM.
- **Merged is deployed, from repo config.** Evidence: `curl -s https://example.com/version` vs the
  merge SHA (CLI uploads omit the commit hash); dashboard start-command overrides. Fix: deploy the
  tested SHA from CI; explicit Dockerfile with `dockerfilePath`, start commands in repo config
  (config-as-code can be ignored on new services). Est.: n/a.
- **Variables are real and complete.** Evidence: `railway variables --json | jq 'keys'` (names
  only; never print values). It reads the linked service; `railway service SERVICE` switches the
  link and only changes local CLI state. Why: platform variables override code defaults and names
  drift. Fix: reference variables to the DB service over the private network (map `DB_HOST`/
  `DB_PORT` when the framework ignores `DATABASE_URL`); seal secrets in the dashboard; every service
  and one-off shell needs all boot-required variables. Est.: n/a.
- **Restores are drilled in isolation.** Native volume restore mounts a replacement on the live
  service and redeploys; never use it as a drill. Restore a logical dump into a throwaway DB; such
  temporary services get no domain, no volume, restart NEVER, no migrate or seed, and are deleted
  after. Est.: n/a.

### Reference notes

- `NEXT_PUBLIC_*` is inlined from build args: declare an `ARG`, fail the build when it is empty,
  never put secrets there.
- Cron is UTC with a 5-minute minimum, one-shot, no domain; it needs the app's DB, cache and
  encryption variables.
- Outbound SMTP is blocked on Free, Trial and Hobby plans (Pro allows it); prefer an HTTPS mail API.
- Generated hosts cannot share auth cookies across web and API; use subdomains of one parent domain.
- Distroless images cannot run a pre-deploy shell; use debian-slim with a non-root user.
- Static outbound IPs are shared and plan-gated; treat IP allowlisting as secondary to token auth.
- `railway logs --json` can put app fields at the top level with an empty `message`; filter with
  jq. Logs can hold tokens and PII: quote only the lines a finding needs, redacted.
- Project tokens cannot read backup schedules or manage volumes. During a platform outage the CLI
  can report "invalid token"; check the status page before rotating anything.

## Cloudflare

- **The origin only accepts Cloudflare.** Evidence: origin firewall/security groups, a platform
  domain still serving the app, `curl -sI https://ORIGIN_HOST.example.com` returning 200 directly. Why:
  direct hits skip WAF and rate limits and let anyone forge `Cf-Ipcountry` or `Cf-Connecting-Ip`.
  Fix: allow only Cloudflare IP ranges, Authenticated Origin Pulls or a Tunnel, SSL mode Full
  (strict). Est.: n/a.
- **Purge prefixes, never everything.** Evidence: `purge_everything` in deploy workflows or scripts.
  Why: it drops the HTML edge cache on the main site for no gain on content-hashed assets. Fix:
  purge by prefix on the asset host only. Est.: n/a.
- **Use `Cf-Ipcountry` before paying for GeoIP.** Cloudflare resolves visitor country at the edge
  on every proxied request for free. Fix: read the header, trust it only when the origin is locked
  to Cloudflare. Est.: the GeoIP plan saved.
- **JS/CSS stay same-origin.** Evidence: the framework asset URL (`ASSET_URL`, `assetPrefix`) set to
  the CDN host. Why: CI and the origin built different hashes and the site went blank. Fix: put
  only media on the CDN; publish and verify assets before activating the app; never sync hashed
  build directories with `--delete` while open pages still reference them. Est.: n/a.
- **Per-user routes bypass the edge cache.** Evidence: cache rules caching HTML;
  `curl -sI https://example.com/account | grep -i cf-cache-status`. Why: one user's page served to
  another. Fix: a bypass list for every per-user route and for requests carrying the auth cookie.
- **DNS has no dangling records.** Why: a dangling CNAME after an origin moves serves 4xx to
  crawlers and can be taken over. Fix: update every CNAME and verification TXT when an origin
  moves; run DNS changes as inspect-then-mutate workflows with a narrowly scoped token. Check
  which account a token reaches with `wrangler whoami` (it prints the email and account IDs; do
  not quote them in the report).
- **Rulesets are patched, not replaced.** Evidence: API `PUT` to a ruleset entrypoint, which
  deletes every existing rule.
- **Workers and Pages deploy on merge and are traceable.** Evidence: `wrangler deployments list`;
  `wrangler versions list`. Why: Workers with no build trigger do not deploy on merge. Fix: deploy
  from CI with the commit hash; verify redirects on the live URL (local previews skip `_redirects`).
- **Wrangler config is safe.** Evidence: secrets in `[vars]` in `wrangler.toml` (plain text);
  placeholder KV IDs (compare with `wrangler kv namespace list`). Fix: `wrangler secret put` (a
  command for the human); real IDs. Mind the Worker script size limit (confirm current limits for
  the plan). Est.: Workers Paid $5/mo when the limit bites.
- **Tunnels.** Need outbound TCP and UDP 7844, and target one loopback port; a strict firewall or a
  server on another port makes the host look online but unreachable. A tunnel terminates TLS at the
  edge, so do not claim end-to-end privacy without app-level encryption. A `workers.dev` Worker
  has no region restriction; do not assume data residency.

## VPS/Docker

- **One host is one failure.** Evidence: a single server in docs or compose with app, DB, cache and
  proxy together. Fix: off-host backups at minimum; managed DB or a second host when RTO demands.
- **Off-host backups with a restore test.** Evidence: backup cron, `restic snapshots`,
  `docker compose config --volumes` for volume names (plain `docker compose config` prints
  interpolated secret values; never run it). Fix: nightly dump plus volume backup to object storage
  in another provider/region; test restores. Est.: for example 50 GB x $0.006 = $0.30/mo.
- **Blue/green aborts on failure.** Why: a script that logs a warning and still switches traffic
  ships a broken release. Fix: abort and keep the old color; no 3xx as success; no default DB
  credentials as a fallback; sessions in DB/Redis, not files. Persist the ACME cert store on a
  volume or redeploys hit Let's Encrypt rate limits.
- **Docker ports bypass the host firewall.** Evidence: `ports: "5432:5432"` in compose; `docker ps`;
  `ss -tlnp`. Why: Docker writes iptables rules that skip ufw, so a published DB port is public.
  Fix: bind to `127.0.0.1:` or drop the port mapping and use the compose network. Anything reaching
  a backend's port directly skips the proxy; strip client `X-Forwarded-*` headers at the proxy.
- **Processes are supervised.** Evidence: `php -S` or a dev server as the production entrypoint;
  background jobs (`schedule:work &`) in the same container; `docker compose config --services`.
  Fix: a real app server, a separate scheduler service, `restart: unless-stopped`, a compose
  `healthcheck`, restart backoff with a cap. Reload PHP-FPM after each deploy (OPcache can serve
  stale code).
- **Static cache headers only on real hashed files.** Fix: `immutable, max-age=1y` only for paths in
  the hashed asset directory that exist (Caddy `file` matcher), so 404s never inherit it.
- **Logs and disk.** Evidence: no `logging` options in compose (json-file grows unbounded);
  `df -h`; `docker system df`. Fix: `max-size`/`max-file`, disk alerts at 80 percent.
- **Images are pinned and lean.** Fix: pin base images and downloaded binaries by tag plus sha256
  (`sha256sum -c` in the Dockerfile); run as non-root in a slim final image; cache dependencies
  separately from sources.
- **Host hygiene.** Evidence: `sshd -T` (password auth, root login), `systemctl status unattended-upgrades`,
  `timedatectl`. Fix: key-only SSH, automatic security updates, time sync, credential files mode 600.
- **Kubernetes, if present.** Evidence: `kubectl get deploy -A -o json | jq '.items[] | select(.spec.replicas == 1) | .metadata.name'`;
  `kubectl get pdb -A`; `kubectl get pvc -A`. Fix: two or more replicas for web, PDBs, readiness
  probes that touch dependencies, PVC backups.
