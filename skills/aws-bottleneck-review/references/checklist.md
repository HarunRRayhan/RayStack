# AWS bottleneck checklist

Work layer by layer along the request path. Each item: what to check, evidence (IaC grep and/or
a read-only command that passes the guard), why it matters, the typical fix, and Est. $/mo where
the fix changes cost.

Conventions:

- Replace `YYYY-MM-DDT00:00:00Z` with literal dates. Default window: last 14 days, `--period 3600`
  (336 points, under the 1440 limit). Use `--statistics Maximum` or `--extended-statistics p99`.
- Logs Insights `start-query` takes epoch seconds. Compute `EPOCH_START`/`EPOCH_END` yourself
  and paste literals; never `$(date ...)` (the guard denies `$`). Insights bills per GB scanned,
  so use a 1-3 day window and `--limit`.
- Replace UPPERCASE placeholders. Add `--region REGION` or `AWS_PROFILE=NAME` as needed.
- Run IaC greps with the agent's search tool or as shown. Prices are us-east-1 on-demand;
  re-check the user's region before quoting a number.

## 0. Quotas and account-wide limits

### Q1. Service quotas near their ceiling
- **Check:** quotas for every service on the path (Lambda concurrency, EC2 vCPUs, ENIs, API
  Gateway rps, Fargate vCPUs) against peak usage.
- **Live:** `aws service-quotas list-service-quotas --service-code lambda --query 'Quotas[].[QuotaName,Value]' --output table`
- **Live:** `aws service-quotas list-service-quotas --service-code ec2 --query 'Quotas[].[QuotaName,QuotaCode,Value]' --output table`
- **Live:** `aws service-quotas list-aws-default-service-quotas --service-code apigateway --query 'Quotas[].[QuotaName,Value]' --output table`
- **Live:** `aws cloudwatch list-metrics --namespace AWS/Usage --query 'Metrics[].Dimensions' --output json | head -n 80`
- **Why:** a quota is a hard wall; traffic above it fails no matter how much compute you add.
  New accounts start with low Lambda concurrency and EC2 vCPU quotas.
- **Also:** subnet IP / ENI exhaustion (`aws ec2 describe-subnets --query 'Subnets[].[SubnetId,AvailabilityZone,AvailableIpAddressCount]' --output table`)
  blocks Lambda-in-VPC, Fargate and ASG scale-out; DynamoDB on-demand tables have a per-table
  throughput quota (40,000 RCU/WCU default); S3 serves about 3,500 writes and 5,500 reads per
  second per prefix, so spread hot keys across prefixes.
- **Fix:** human files a quota increase; add a CloudWatch alarm on the `AWS/Usage` metric at 80%.
- **Est. $/mo:** n/a (increases are free; alarms about $0.10 each).

### Q2. Control-plane API throttling by your own tooling
- **Check:** scripts, scanners or deploy tools that call AWS APIs in loops across many
  accounts or regions; `ThrottlingException` / `Rate exceeded` in logs.
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'ThrottlingException|Rate exceeded|TooManyRequests' .`
- **Why:** API rate limits are per account, per region, per API. A busy scanner can starve
  autoscaling and deploys of the same API.
- **Fix:** rate budget per (connection, service) with a token bucket; after N throttled
  retries mark the chunk throttled and move on; chunk by service x region and write the
  checkpoint in the same transaction as the results so a crash resumes.
- **Est. $/mo:** n/a.

## 1. Edge (CloudFront, WAF)

### E1. Cache hit rate and origin timeout
- **Check:** cache hit rate, origin response timeout (default 30 s), whether static assets bypass
  the cache. `CacheHitRate` exists only if additional metrics are enabled on the distribution
  (opt-in, paid); otherwise use `5xxErrorRate` and origin load.
- **Live:** `aws cloudfront list-distributions --query 'DistributionList.Items[].[Id,DomainName,Origins.Items[0].DomainName]' --output table`
- **Live:** `aws cloudfront get-distribution-config --id DISTRIBUTION_ID --query 'DistributionConfig.Origins.Items[].[Id,CustomOriginConfig.OriginReadTimeout,CustomOriginConfig.OriginKeepaliveTimeout]'`
- **Live:** `aws cloudwatch get-metric-statistics --region us-east-1 --namespace AWS/CloudFront --metric-name 5xxErrorRate --dimensions Name=DistributionId,Value=DISTRIBUTION_ID Name=Region,Value=Global --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Maximum`
- **Why:** every miss is load on the narrowest hop behind it. A short origin timeout turns slow
  origin calls into 504s at the edge.
- **Fix:** cache policy with long TTL for hashed assets; raise `OriginReadTimeout` only when the
  origin legitimately needs it, otherwise make the origin faster.
- **Est. $/mo:** usually negative (offload cuts origin compute and egress); n/a without traffic data.

## 2. Load balancer and API Gateway

### L1. API Gateway timeout vs function timeout
- **Check:** integration timeout on buffered REST/HTTP APIs (29 s REST default, 30 s HTTP API
  max) against Lambda `Timeout` and any long-running or streaming endpoint (SSE, long polling).
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'timeout_milliseconds|TimeoutInMillis|timeoutInMillis|integration_timeout' .`
- **Live:** `aws lambda list-functions --query 'Functions[].[FunctionName,Timeout,MemorySize,Runtime]' --output table`
- **Why:** the gateway cuts the client at about 29 s while the function keeps running and
  billing. SSE through API Gateway dies at the same mark.
- **Fix:** set the function timeout just below the gateway (28 s); move long work to a queue and
  return 202; serve streams over Lambda response streaming (Function URL, or REST API response
  streaming where available) or Streamable HTTP with a fresh transport per invocation.
- **Est. $/mo:** saves the billed seconds past the cut: invocations x (Timeout - 29 s) x GB x
  $0.0000166667.

### L2. API Gateway throttling (429)
- **Check:** account limit (10,000 rps, 5,000 burst per region by default), stage and method
  throttles, usage plans; `4XXError` and `Count` peaks.
- **Live:** `aws apigateway get-stages --rest-api-id API_ID --query 'item[].[stageName,methodSettings]'`
- **Live:** `aws apigatewayv2 get-stages --api-id API_ID --query 'Items[].[StageName,DefaultRouteSettings]'`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/ApiGateway --metric-name 4XXError --dimensions Name=ApiName,Value=API_NAME --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Sum`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/ApiGateway --metric-name 4xx --dimensions Name=ApiId,Value=API_ID --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Sum`
  (HTTP APIs: `ApiId` dimension, lower-case `4xx`/`5xx` metric names.)
- **Why:** 429s look like app errors but are a configured limit.
- **Fix:** raise stage throttles to match the backend's real capacity; request an account
  increase; cache GET responses at CloudFront.
- **Est. $/mo:** n/a.

### L3. API Gateway latency split
- **Check:** `Latency` minus `IntegrationLatency` (gateway overhead, authorizers) vs
  `IntegrationLatency` (backend), at p99.
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/ApiGateway --metric-name IntegrationLatency --dimensions Name=ApiName,Value=API_NAME --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --extended-statistics p99`
- **Why:** tells you whether to look at authorizers/mapping or at the backend.
- **Fix:** cache Lambda authorizer results (`authorizerResultTtlInSeconds`); otherwise follow the
  backend.
- **Est. $/mo:** n/a.

### L4. ALB saturation and errors
- **Check:** `TargetResponseTime` p99, `HTTPCode_ELB_5XX_Count` (502/503/504 from the LB) vs
  `HTTPCode_Target_5XX_Count` (from the app), `RejectedConnectionCount`, `UnHealthyHostCount`, idle timeout (60 s default) vs long requests.
- **Live:** `aws elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,Type,Scheme,AvailabilityZones[].ZoneName]' --output json`
- **Live:** `aws elbv2 describe-load-balancer-attributes --load-balancer-arn LB_ARN --output table`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name TargetResponseTime --dimensions Name=LoadBalancer,Value=app/LB_NAME/LB_ID --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --extended-statistics p99`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name HTTPCode_ELB_5XX_Count --dimensions Name=LoadBalancer,Value=app/LB_NAME/LB_ID --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Sum`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name HTTPCode_Target_5XX_Count --dimensions Name=LoadBalancer,Value=app/LB_NAME/LB_ID --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Sum`
- **Why:** ELB 5xx with healthy targets means targets are too few, too slow, or closing
  keep-alive connections before the LB does.
- **Fix:** app keep-alive timeout above the LB idle timeout; scale on `RequestCountPerTarget`;
  raise idle timeout only for known long requests.
- **Est. $/mo:** n/a until target count changes; then targets x instance price.

### L5. Health checks that lie
- **Check:** health check path, matcher and grace; whether the route touches real dependencies;
  nginx prefix `location /health` shadowing deeper routes like `/health/...`.
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'health_check|HealthCheckPath|healthCheck|location +/health' .`
- **Live:** `aws elbv2 describe-target-groups --query 'TargetGroups[].[TargetGroupName,HealthCheckPath,HealthCheckIntervalSeconds,UnhealthyThresholdCount,Matcher.HttpCode]' --output table`
- **Live:** `aws elbv2 describe-target-health --target-group-arn TG_ARN --output table`
- **Why:** a static 200 keeps a broken target in rotation; a too-strict check kills healthy
  targets during deploys and cold resumes.
- **Fix:** exact-match location (`location = /health`); a shallow liveness check for the LB and a
  separate deep readiness check for alerts.
- **Est. $/mo:** n/a.

## 3. Compute: Lambda

### C1. Concurrency, throttles and reserved concurrency
- **Check:** `ConcurrentExecutions` Maximum vs account limit; `Throttles` Sum; reserved
  concurrency per function (one greedy function can starve the rest).
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'reserved_concurrent_executions|ReservedConcurrentExecutions|reservedConcurrency' .`
- **Live:** `aws lambda get-account-settings --query 'AccountLimit'`
- **Live:** `aws lambda get-function-concurrency --function-name FUNCTION_NAME`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Throttles --dimensions Name=FunctionName,Value=FUNCTION_NAME --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Sum`
- **Live:** `aws cloudwatch get-metric-data --metric-data-queries '[{"Id":"c","MetricStat":{"Metric":{"Namespace":"AWS/Lambda","MetricName":"ConcurrentExecutions"},"Period":3600,"Stat":"Maximum"}}]' --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --query 'MetricDataResults[].Values' --output json`
- **Why:** throttled sync calls fail with 429; throttled async/queue calls back up silently.
- **Fix:** reserved concurrency on critical functions, a cap on noisy ones; quota increase.
- **Est. $/mo:** n/a (reserved concurrency is free).

### C2. Queue-driven concurrency stampede
- **Check:** SQS event source mappings with no `MaximumConcurrency`; memory-heavy or long jobs fed
  by a queue.
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'aws_lambda_event_source_mapping|EventSourceMapping|maximum_concurrency|MaximumConcurrency' .`
  (flag mappings with no `scaling_config.maximum_concurrency`).
- **Live:** `aws lambda list-event-source-mappings --function-name FUNCTION_NAME --query 'EventSourceMappings[].[EventSourceArn,BatchSize,ScalingConfig.MaximumConcurrency,FunctionResponseTypes]' --output json`
- **Why:** an SQS mapping scales pollers by about 300 concurrent invocations per minute, up to
  1,000 (or the account limit), until the backlog drains. One bug that makes
  each job slow turns 30 queued messages into 30 parallel multi-GB invocations, starving the
  database and the account concurrency pool.
- **Fix:** set `scaling_config { maximum_concurrency = 2..N }` sized to what the downstream DB can
  take; add an error-rate circuit breaker that disables the mapping (human runs it). Pair with
  M1/M2: raise `maxReceiveCount` to at least 5.
- **Est. $/mo:** risk, not saving: concurrency x memory GB x seconds x $0.0000166667 per burst.

### C3. Timeouts, retries and the cost of failure
- **Check:** functions near the 15-minute cap (no SIGTERM, billed in full); retry count
  (`maxReceiveCount`, async `MaximumRetryAttempts`) on jobs that always fail the same way;
  `Duration` Maximum close to `Timeout`.
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'maxReceiveCount|max_receive_count|maximum_retry_attempts|MaximumRetryAttempts' .`
- **Live:** `aws lambda get-function-event-invoke-config --function-name FUNCTION_NAME`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Duration --dimensions Name=FunctionName,Value=FUNCTION_NAME --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Maximum`
- **Why:** default retries multiply the cost of a deterministic failure (3 tries of a 14-minute
  job is 42 billed minutes for nothing). A timeout loses all progress.
- **Fix:** checkpoint each step so a retry skips finished work; set `maxReceiveCount` from the
  real cost of one timeout; send to a DLQ fast; move work over 15 minutes to Step Functions or
  Fargate.
- **Est. $/mo:** waste removed = failures/mo x (retries - 1) x seconds x GB x $0.0000166667,
  e.g. 100 x 2 x 840 s x 5 GB x $0.0000166667 = $14.00.

### C4. Cold starts
- **Check:** `Init Duration` share and p99 from REPORT lines; package size and init code;
  warm-up pings used as the fix. VPC attachment no longer adds much cold start (Hyperplane ENIs);
  don't blame it without data.
- **Live:** `aws logs start-query --log-group-name /aws/lambda/FUNCTION_NAME --start-time EPOCH_START --end-time EPOCH_END --limit 100 --query-string 'filter @type = "REPORT" | stats count(@initDuration) as cold, count(*) as total, pct(@initDuration, 99) as p99init'`
- **Live:** `aws logs get-query-results --query-id QUERY_ID`
- **Why:** a warm-up ping keeps one execution environment warm, not N; concurrent spikes still
  cold start.
- **Fix:** provisioned concurrency sized to the spike for latency-critical paths; SnapStart for
  Java/Python/.NET; trim dependencies and lazy-load at init; drop the VPC when the function only
  calls DynamoDB or public APIs (that removes NAT cost, see N1).
- **Est. $/mo:** provisioned concurrency = envs x GB x 2,628,000 s x $0.0000041667,
  e.g. 5 x 1 GB = $54.75.

### C5. Memory sizing (CPU scales with memory)
- **Check:** CPU-bound functions at low memory; `Max Memory Used` vs `MemorySize`.
- **Live:** `aws lambda get-function-configuration --function-name FUNCTION_NAME --query '[MemorySize,Timeout,Architectures,EphemeralStorage.Size]'`
- **Why:** under 1,769 MB a function gets less than one vCPU; doubling memory can halve duration
  at the same cost.
- **Fix:** power-tune memory; move to `arm64` where dependencies allow.
- **Est. $/mo:** GB-s before minus after x $0.0000166667; arm64 is about 20% cheaper per GB-s.

## 4. Compute: ECS, Fargate, EC2

### C6. T-class CPU credits
- **Check:** credit mode first. T3/T3a/T4g default to unlimited: the symptom is
  `CPUSurplusCreditsCharged` on the bill, not throttling. T2 (and any instance set to standard)
  throttles to baseline when `CPUCreditBalance` hits 0. Baseline varies by size, 5-40% per vCPU;
  compare `CPUUtilization` average to that size's baseline.
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'instance_type *= *"?(t2|t3|t3a|t4g)|InstanceType: *(t2|t3|t3a|t4g)|db.t[234]' .`
- **Live:** `aws ec2 describe-instance-credit-specifications --query 'InstanceCreditSpecifications[].[InstanceId,CpuCredits]' --output table`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUCreditBalance --dimensions Name=InstanceId,Value=INSTANCE_ID --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Minimum`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUSurplusCreditsCharged --dimensions Name=InstanceId,Value=INSTANCE_ID --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Sum`
- **Why:** a drained standard-mode instance runs at its baseline and looks like a slow app; an
  unlimited one stays fast but bills surplus credits that can exceed a bigger instance. Same for
  `db.t*` RDS classes (RDS T3/T4g also default to unlimited).
- **Fix:** fixed-performance class with the same vCPU count when the average sits above baseline
  (t3.medium has 2 vCPU, so m7g.large, not m7g.medium).
- **Est. $/mo:** new price - old price - surplus charges removed, e.g. t3.medium $30.37 to
  m7g.large $59.57 = +$29.20, minus surplus at $0.05 per vCPU-hour (worth it above 584 surplus
  vCPU-hours/mo).

### C7. Autoscaling ceilings
- **Check:** ASG or ECS service at `MaxSize`/max capacity during peaks; scaling on CPU when the
  limit is connections or queue depth.
- **Live:** `aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[].[AutoScalingGroupName,MinSize,MaxSize,DesiredCapacity,AvailabilityZones]' --output json`
- **Live:** `aws application-autoscaling describe-scalable-targets --service-namespace ecs --query 'ScalableTargets[].[ResourceId,MinCapacity,MaxCapacity]' --output table`
- **Live:** `aws application-autoscaling describe-scaling-policies --service-namespace ecs --output json`
- **Why:** a ceiling hit during peak is a capacity outage that metrics show as high latency.
- **Fix:** raise max; scale on `RequestCountPerTarget` or SQS backlog per task; check the DB can
  take the extra connections first.
- **Also:** ECS container `CPUUtilization`/`MemoryUtilization` Maximum and stopped tasks with
  `OutOfMemoryError` or exit 137 (`aws ecs list-tasks --cluster CLUSTER --desired-status STOPPED`,
  then `aws ecs describe-tasks --cluster CLUSTER --tasks TASK_ARN --query 'tasks[].[stoppedReason,containers[].reason]'`).
- **Est. $/mo:** added tasks x task price, e.g. 2 x Fargate 1 vCPU/2 GB ($36.04) = $72.08.

### C8. ECS health check grace during dependency resume
- **Check:** container `healthCheck.startPeriod` and service `healthCheckGracePeriodSeconds`
  when the app waits on Aurora Serverless resume (10-20 s) or slow migrations at boot.
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'startPeriod|start_period|health_check_grace_period_seconds|HealthCheckGracePeriodSeconds' .`
- **Live:** `aws ecs describe-services --cluster CLUSTER --services SERVICE --query 'services[].[serviceName,healthCheckGracePeriodSeconds,desiredCount,runningCount]' --output table`
- **Why:** without grace ECS kills healthy tasks in a loop and the service never stabilizes.
- **Fix:** `startPeriod` 60 s; grace period above worst-case boot time.
- **Est. $/mo:** n/a.

### C9. EBS IOPS and throughput caps
- **Check:** current IOPS and throughput per volume first. gp2 baseline is 3 IOPS/GB (minimum
  100, up to 16,000), so gp2 over about 1 TB already exceeds 3,000 IOPS. `BurstBalance` exists
  only for gp2, st1 and sc1 (gp2 under 1 TB bursts to 3,000). `VolumeQueueLength` high; instance
  EBS bandwidth cap (`EBSIOBalance%`, `EBSByteBalance%` on smaller instance sizes).
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'volume_type|VolumeType|"gp2"|gp2' .`
- **Live:** `aws ec2 describe-volumes --query 'Volumes[].[VolumeId,VolumeType,Size,Iops,Throughput,Attachments[0].InstanceId]' --output table`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/EBS --metric-name BurstBalance --dimensions Name=VolumeId,Value=VOLUME_ID --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Minimum`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name EBSIOBalance% --dimensions Name=InstanceId,Value=INSTANCE_ID --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Minimum`
- **Why:** an empty burst bucket drops disk to baseline; every query and write slows at once.
- **Fix:** gp2 to gp3 with provisioned IOPS and throughput at least equal to the gp2 baseline
  and observed peak (gp3 starts at 3,000 IOPS / 125 MiB/s at any size; a 2,000 GB gp2 has 6,000
  IOPS and up to 250 MiB/s, so converting at defaults halves it). Larger instance when the
  instance cap, not the volume, is the limit.
- **Est. $/mo:** gp2 $0.10/GB vs gp3 $0.08/GB plus $0.005 per IOPS above 3,000 and $0.04 per
  MiB/s above 125, e.g. 500 GB: $50.00 to $40.00 = -$10.00; 2,000 GB: $200.00 to $160.00 +
  3,000 x $0.005 + 125 x $0.04 = $180.00, saves $20.00.

## 5. Queues (SQS, SNS, EventBridge)

### M1. Visibility timeout vs consumer timeout
- **Check:** `VisibilityTimeout` at least 6x the Lambda `Timeout`; partial batch responses.
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'visibility_timeout_seconds|VisibilityTimeout|ReportBatchItemFailures|function_response_types' .`
- **Live:** `aws sqs get-queue-attributes --queue-url QUEUE_URL --attribute-names VisibilityTimeout RedrivePolicy MessageRetentionPeriod`
- **Why:** a message becomes visible again while still processing, so it runs twice; one bad
  message without `batchItemFailures` retries the whole batch.
- **Fix:** visibility timeout >= 6x function timeout; enable `ReportBatchItemFailures` and return
  `batchItemFailures`; let throttling errors fail back to the queue as backpressure. With a Lambda
  consumer, a throttled receive still counts toward `maxReceiveCount`, so backpressure needs
  `maxReceiveCount` >= 5 and `MaximumConcurrency` (C2) or good messages land in the DLQ (M2).
- **Est. $/mo:** removes duplicate invocations: duplicates/mo x seconds x GB x $0.0000166667.

### M2. Backlog age and DLQ
- **Check:** `ApproximateAgeOfOldestMessage` Maximum, `ApproximateNumberOfMessagesVisible`,
  a DLQ on every queue, DLQ depth and alarm.
- **Live:** `aws sqs list-queues --output text`
- **Live:** `aws sqs get-queue-attributes --queue-url QUEUE_URL --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/SQS --metric-name ApproximateAgeOfOldestMessage --dimensions Name=QueueName,Value=QUEUE_NAME --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Maximum`
- **Why:** a growing age means consumers are slower than producers; without a DLQ a poison
  message blocks or loops until retention deletes it.
- **Fix:** DLQ with an alarm on depth > 0. `maxReceiveCount`: at least 5 for a Lambda event
  source mapping (throttled receives burn the count, see M1), together with `MaximumConcurrency`
  (C2); size it down only from the real cost of one failed run (C3). Scale consumers on backlog
  per consumer; fix the slow hop downstream first.
- **Est. $/mo:** n/a (SQS requests are cents).

### M3. Non-SQS job queues (Redis/DB-backed workers)
- **Check:** depth = pending + delayed + reserved; Redis key prefix stripped before lookups;
  Redis Cluster pipelines across slots read as 0.
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'QUEUE_CONNECTION|queue.*prefix|REDIS_PREFIX|bull|sidekiq|celery' .`
- **Live:** `redis-cli -h REDIS_HOST INFO keyspace`
- **Why:** counting only pending under-reports the backlog, so autoscaling never fires.
- **Fix:** monitor all three states per queue; read each key directly in cluster mode.
- **Est. $/mo:** n/a.

## 6. Data stores

### D1. RDS/Aurora connection limits
- **Check:** `DatabaseConnections` Maximum vs `max_connections` (default is derived from instance
  memory); Lambda or autoscaled tasks opening a connection each.
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'max_connections|aws_db_proxy|DBProxy|pool_size|DB_POOL|connection_limit' .`
- **Live:** `aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,Engine,MultiAZ,DBParameterGroups[0].DBParameterGroupName]' --output table`
- **Live:** `aws rds describe-db-parameters --db-parameter-group-name PARAM_GROUP --output text | grep max_connections`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name DatabaseConnections --dimensions Name=DBInstanceIdentifier,Value=DB_ID --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Maximum`
- **Why:** at the limit new connections fail outright; each idle Postgres connection also costs
  memory.
- **Fix:** RDS Proxy or PgBouncer; cap app pool x max tasks below `max_connections`; cap Lambda
  concurrency (C1, C2).
- **Est. $/mo:** RDS Proxy = vCPUs x $0.015 x 730, e.g. 2 vCPU = $21.90.

### D2. RDS CPU, memory, storage IO
- **Check:** `CPUUtilization` p99, `FreeableMemory` Minimum, `DiskQueueDepth`, `ReadIOPS` +
  `WriteIOPS` vs provisioned IOPS, `BurstBalance` on gp2, `CPUCreditBalance` on `db.t*`.
- **Live:** `aws rds describe-db-instances --db-instance-identifier DB_ID --query 'DBInstances[].[StorageType,AllocatedStorage,Iops,StorageThroughput]'`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name DiskQueueDepth --dimensions Name=DBInstanceIdentifier,Value=DB_ID --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Maximum`
- **Live:** `aws pi get-resource-metrics --service-type RDS --identifier DB_RESOURCE_ID --metric-queries '[{"Metric":"db.load.avg","GroupBy":{"Group":"db.wait_event"}}]' --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period-in-seconds 3600`
- **Why:** the DB is usually the narrowest hop; Performance Insights wait events say whether it
  is CPU, IO or locks (free retention is 7 days, so older windows need paid retention or
  CloudWatch). Hand query-level work to `database-review`.
- **Fix:** gp3 with provisioned IOPS; read replica for read-heavy paths; larger class only after
  slow queries are fixed.
- **Est. $/mo:** class delta x 730 h, or replica = one more instance price.

### D3. Aurora Serverless scaling and resume
- **Check:** min ACU (0 means pause and a 10-20 s first-connection resume), max ACU reached,
  `ServerlessDatabaseCapacity` Maximum.
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'min_capacity|max_capacity|MinCapacity|MaxCapacity|seconds_until_auto_pause' .`
- **Live:** `aws rds describe-db-clusters --query 'DBClusters[].[DBClusterIdentifier,ServerlessV2ScalingConfiguration]' --output json`
- **Why:** max ACU is a hard ceiling; resume latency trips app and LB timeouts.
- **Fix:** min ACU above 0 for user-facing paths; raise max; app retries the first connection.
- **Est. $/mo:** each 0.5 ACU kept warm = 0.5 x $0.12 x 730 = $43.80.

### D4. DynamoDB throttling
- **Check:** `ThrottledRequests`, `ReadThrottleEvents`, `WriteThrottleEvents`; provisioned
  capacity without autoscaling; hot partition keys.
- **Live:** `aws dynamodb describe-table --table-name TABLE --query 'Table.[BillingModeSummary,ProvisionedThroughput,GlobalSecondaryIndexes[].IndexName]'`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/DynamoDB --metric-name WriteThrottleEvents --dimensions Name=TableName,Value=TABLE --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Sum`
- **Why:** throttles with spare table capacity mean one partition key is hot (3,000 RCU / 1,000
  WCU per partition).
- **Fix:** on-demand for spiky load; better key distribution; autoscaling on provisioned tables.
- **Est. $/mo:** n/a without request volume.

### D5. ElastiCache saturation
- **Check:** `EngineCPUUtilization` (single-threaded Redis), `Evictions`, `CurrConnections`,
  `DatabaseMemoryUsagePercentage`.
- **Live:** `aws elasticache describe-cache-clusters --query 'CacheClusters[].[CacheClusterId,CacheNodeType,Engine,PreferredAvailabilityZone]' --output table`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/ElastiCache --metric-name EngineCPUUtilization --dimensions Name=CacheClusterId,Value=CACHE_ID --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Maximum`
- **Why:** evictions push load back onto the database; a hot engine thread caps every request.
- **Fix:** larger node or cluster mode; TTLs; separate cache from queue workloads.
- **Est. $/mo:** node price delta x 730 h.

## 7. Network and egress

### N1. NAT Gateway on the hot path
- **Check:** Lambda/tasks in private subnets reaching S3, DynamoDB or public APIs through NAT;
  `ErrorPortAllocation`, `PacketsDropCount`; one NAT for all AZs.
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'aws_nat_gateway|NatGateway|aws_vpc_endpoint|VPCEndpoint|vpc_config' .`
- **Live:** `aws ec2 describe-nat-gateways --query 'NatGateways[].[NatGatewayId,SubnetId,State]' --output table`
- **Live:** `aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[].[ServiceName,VpcEndpointType]' --output table`
- **Live:** `aws cloudwatch get-metric-statistics --namespace AWS/NATGateway --metric-name ErrorPortAllocation --dimensions Name=NatGatewayId,Value=NAT_ID --start-time YYYY-MM-DDT00:00:00Z --end-time YYYY-MM-DDT00:00:00Z --period 3600 --statistics Sum`
- **Why:** NAT adds a standing cost, per-GB charges, and a per-destination connection cap
  (about 55,000 per destination IP).
- **Fix:** S3/DynamoDB gateway endpoints (free); drop VPC from functions that need no private
  resources; one NAT per AZ for resilience.
- **Est. $/mo:** NAT $0.045 x 730 = $32.85 each plus $0.045/GB; a gateway endpoint saves
  GB x $0.045.

### N2. Outbound calls, streams and deadlines
- **Check:** every outbound HTTP call has a connect and total deadline; stream proxies read to
  each frame delimiter, not fixed blocks; batch clients check transfer completion, not only
  status.
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'CURLOPT_TIMEOUT|connect_?timeout|read_?timeout|requestTimeout|AbortSignal.timeout|read.8192.|chunk_size|text/event-stream' .`
- **Why:** a request that never resolves pins a worker or a concurrency slot; an SSE proxy
  reading 8 KiB blocks stalls small frames until the buffer fills; a pooled client can report
  200 from partial headers after an aborted transfer.
- **Fix:** explicit deadlines and stale-stream detection; frame-delimited reads with a real-TLS
  regression test; compare `curl -N` through the proxy vs direct (human runs it).
- **Est. $/mo:** n/a.

## 8. Availability (single-AZ and single points)

### A1. Single-AZ resources on the path
- **Check:** RDS `MultiAZ` false, ElastiCache without replicas, ASG/ECS subnets in one AZ,
  one NAT, one instance behind the LB.
- **IaC:** `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'multi_az|MultiAZ|availability_zone|subnet_ids|automatic_failover' .`
- **Live:** `aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,MultiAZ,AvailabilityZone,BackupRetentionPeriod]' --output table`
- **Live:** `aws ecs describe-services --cluster CLUSTER --services SERVICE --query 'services[].networkConfiguration.awsvpcConfiguration.subnets'`
- **Why:** one AZ event takes the whole path down; a single data store with no tested restore
  is Critical.
- **Fix:** Multi-AZ for production data; spread compute over at least 2 AZs; replica for cache.
- **Est. $/mo:** Multi-AZ about doubles the instance price, e.g. db.t4g.medium $47.45 more.

### A2. Alarms on the limits found above
- **Check:** CloudWatch alarms exist for every limit in this review (throttles, connections,
  credits, burst balance, queue age, 5xx).
- **Live:** `aws cloudwatch describe-alarms --query 'MetricAlarms[].[AlarmName,Namespace,MetricName,Threshold,StateValue]' --output table`
- **Why:** a limit without an alarm is found by users first.
- **Fix:** one alarm per limit at 80% of the ceiling, routed to a human.
- **Est. $/mo:** $0.10 per standard alarm.

## 9. Measurement hygiene (apply to every finding)

- State window, statistic and sample size. Never conclude from `Average` or one short sample.
- A passing health route is not availability evidence (L5).
- Load tests from a loaded laptop or a single local process are invalid for hosted throughput.
- Measure page latency under concurrent CPU-heavy jobs before recommending a separate worker
  host; run independent calls in parallel before buying capacity.
- Test a request that never resolves and a dropped stream before calling a path ready for
  unattended traffic.
