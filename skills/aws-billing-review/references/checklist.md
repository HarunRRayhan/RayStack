# AWS billing checklist

Each item: what to check, where the evidence comes from (**IaC** grep pattern and/or a
read-only **Cmd**), the **Fix**, and how to estimate **$/mo**.

Conventions:

- Prices are us-east-1 on-demand list prices. State them in the finding and scale for other
  regions. 730 hours per month.
- Replace example dates with the last 3 full months, and IDs like `i-0123...`, `my-bucket`,
  `my-fn` with real ones from earlier output.
- Add `--profile <name>` or `--region <region>` as the user chose. One CLI call per command.
- Cost Explorer (`aws ce ...`) calls cost $0.01 each. Run each one once. If the output has a
  `NextPageToken`, results are truncated: rerun with `--next-page-token <token>` (another $0.01)
  before you total anything.
- IaC greps skip `.git`, `node_modules`, `.terraform`, `cdk.out` and `*.tfstate*` (state files
  hold secrets). Never print secret values found in any file.

## A. Where the money goes (start here)

### A1. Top services by cost
- **Check:** the 10 to 15 services that make up most of the bill, month over month.
- **Cmd:** `aws ce get-cost-and-usage --time-period Start=2026-07-01,End=2026-10-01 --granularity MONTHLY --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE --output json | jq -r '.ResultsByTime[] | .TimePeriod.Start + " " + (.Groups | sort_by(.Metrics.UnblendedCost.Amount | tonumber) | reverse | .[0:15][] | .Metrics.UnblendedCost.Amount + " " + .Keys[0])'`
- **Fix:** none on its own. Rank the rest of this checklist by these numbers.
- **$/mo:** this is the baseline. Quote the latest full month total in the summary.

### A2. Usage types inside the top services
- **Check:** what kind of usage drives each top service. Data transfer, NAT, public IPv4 and
  EBS show up under "EC2 - Other", not as their own services.
- **Cmd:** `aws ce get-cost-and-usage --time-period Start=2026-09-01,End=2026-10-01 --granularity MONTHLY --metrics UnblendedCost UsageQuantity --group-by Type=DIMENSION,Key=USAGE_TYPE --output json | jq -r '.ResultsByTime[].Groups[] | [.Metrics.UnblendedCost.Amount, .Keys[0], .Metrics.UsageQuantity.Amount] | @tsv' | sort -rn | head -40`
- **Fix:** map each large usage type to a section below (`DataTransfer-Regional-Bytes` = cross-AZ, `NatGateway-Bytes` = NAT, `PublicIPv4` = public IPs, `TimedStorage-ByteHrs` = S3, `EBS:VolumeUsage.gp2` = gp2).
- **$/mo:** the Amount column is the monthly cost of that usage type.

### A3. Credits hiding real burn
- **Check:** credits that net the bill to near zero. The real run rate is the `Usage` row.
- **Cmd:** `aws ce get-cost-and-usage --time-period Start=2026-09-01,End=2026-10-01 --granularity MONTHLY --metrics UnblendedCost --group-by Type=DIMENSION,Key=RECORD_TYPE --output json | jq -r '.ResultsByTime[].Groups[] | [.Keys[0], .Metrics.UnblendedCost.Amount] | @tsv'`
- **Fix:** report the `Usage` total as the real bill and the credit expiry date as a risk.
- **$/mo:** `Usage` amount = what the account costs once credits run out.

### A4. Spend in regions nobody uses
- **Check:** cost in regions outside the user's stated scope (forgotten test servers, IPs, NATs).
- **Cmd:** `aws ce get-cost-and-usage --time-period Start=2026-09-01,End=2026-10-01 --granularity MONTHLY --metrics UnblendedCost --group-by Type=DIMENSION,Key=REGION --output json | jq -r '.ResultsByTime[].Groups[] | [.Metrics.UnblendedCost.Amount, .Keys[0]] | @tsv' | sort -rn`
- **Fix:** list the resources in each stray region (rerun the EC2/EBS/EIP/NAT commands below with `--region <region>`), then a cleanup list for the human.
- **$/mo:** the region's row.

### A5. AWS's own savings recommendations
- **Check:** what AWS already flags: rightsizing, idle resources, Graviton, commitments, in one list with $ estimates.
- **Cmd:** `aws cost-optimization-hub list-recommendations --region us-east-1 --query 'items[].[estimatedMonthlySavings,actionType,currentResourceType,resourceId]' --output text | sort -rn | head -30`
- **Cmd:** `aws ce get-rightsizing-recommendation --service AmazonEC2 --query 'RightsizingRecommendations[].[CurrentInstance.ResourceId,RightsizingType,CurrentInstance.ResourceDetails.EC2ResourceDetails.InstanceType]' --output table`
- **Fix:** use these as leads, then confirm each with the matching section below. Cost Optimization Hub must be opted in (an empty or access-denied result means it is off; recommend enabling it, human).
- **$/mo:** Cost Optimization Hub's `estimatedMonthlySavings`. Do not add overlapping items twice (rightsizing and a Savings Plan for the same instance).

## B. Compute: EC2, Fargate, Lambda

### B1. Idle or oversized EC2
- **Check:** instances under 5% average CPU for 7+ days, or Compute Optimizer "Overprovisioned".
- **IaC:** `grep -rnE 'instance_type|InstanceType' --include='*.tf' --include='*.yaml' --include='*.json' --include='*.ts' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Cmd:** `aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].[InstanceId,InstanceType,LaunchTime,Placement.AvailabilityZone]' --output table`
- **Cmd:** `aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --dimensions Name=InstanceId,Value=i-0123456789abcdef0 --start-time 2026-10-14T00:00:00Z --end-time 2026-10-28T00:00:00Z --period 86400 --statistics Average Maximum --query 'Datapoints[].[Timestamp,Average,Maximum]' --output text`
- **Cmd:** `aws compute-optimizer get-ec2-instance-recommendations --query 'instanceRecommendations[].[instanceArn,finding,currentInstanceType,recommendationOptions[0].instanceType]' --output table`
- **Fix:** stop or terminate idle ones (human, after owner confirms); drop one size for oversized ones in IaC. Check memory too: CPU alone misses memory-bound apps.
- **$/mo:** (current hourly price - target hourly price) x 730. One size down halves the price in the same family (e.g. m7i.xlarge $0.2016/h to m7i.large $0.1008/h = $73.58/mo).

### B2. Graviton candidates
- **Check:** x86 instances, RDS classes, Fargate tasks and Lambdas running Linux workloads with no x86-only binaries.
- **IaC:** `grep -rnE 'instance_type.*(m[5-7]i?|c[5-7]i?|r[5-7]i?|t3)[.]|cpu_architecture|architectures' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Cmd:** (Commands for you to run: the guard blocks Lambda config reads, which include env vars; keep a `--query` that leaves out Environment) `aws lambda list-functions --query 'Functions[].[FunctionName,Architectures[0],MemorySize,Runtime]' --output table`
- **Fix:** switch to the `g` family (m7g, c7g, r7g, t4g, db.m7g) or `arm64` / `ARM64`. Rebuild container images multi-arch first.
- **$/mo:** about 20% of the instance cost for EC2/RDS (compare the two list prices), 20% of Lambda duration cost, 20% of Fargate vCPU+memory cost.

### B3. Dev and staging running 24/7
- **Check:** non-prod EC2, RDS, ECS services and NAT gateways running all week. Office hours are about 50 of 168 hours.
- **IaC:** `grep -rnE 'environment.*(dev|staging|test)|aws_scheduler_schedule|aws_autoscaling_schedule' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' . | cut -d: -f1,2` (file:line only: `environment` lines can hold secret values)
- **Cmd:** `aws resourcegroupstaggingapi get-resources --tag-filters Key=Environment,Values=dev,staging,test --query 'ResourceTagMappingList[].ResourceARN' --output text`
- **Cmd:** `aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus,MultiAZ,TagList]' --output json`
- **Fix:** EventBridge Scheduler stop/start (or Instance Scheduler) in IaC; downsize non-prod and turn off Multi-AZ there. A stopped RDS instance starts itself after 7 days, so the stop must be recurring. Storage still bills while stopped.
- **$/mo:** compute cost x (1 - 50/168) = about 70% of instance hours saved for office-hours-only. Do not count storage.

### B4. Compute model fits the load shape
- **Check:** steady 24/7 work on Lambda, or spiky/idle work on always-on EC2/Fargate.
- **IaC:** `grep -rnE 'aws_lambda_function|Lambda::Function|aws_ecs_service|desired_count' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Fix:** steady load to Fargate or EC2 (with a Savings Plan); spiky load to Lambda (scales to zero); interruptible batch to Spot (adds ops work, say so).
- **$/mo:** price both: Lambda = requests/mo x avg duration s x memory GB x $0.0000166667 + requests x $0.20/1M. Fargate = vCPU x $0.04048 x 730 + GB x $0.004445 x 730.

### B5. Lambda memory sizing
- **Check:** configured `memory_size` far above "Max Memory Used", or CPU-bound jobs where more memory stopped helping.
- **IaC:** `grep -rnE 'memory_size|MemorySize|memorySize' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Cmd:** `aws logs filter-log-events --log-group-name /aws/lambda/my-fn --filter-pattern REPORT --max-items 50 --query 'events[].message' --output text | grep -o 'Max Memory Used: [0-9]* MB' | sort | uniq -c`
- **Cmd:** `aws compute-optimizer get-lambda-function-recommendations --query 'lambdaFunctionRecommendations[].[functionArn,finding,currentMemorySize,memorySizeRecommendationOptions[0].memorySize]' --output table`
- **Fix:** set memory to about 1.5x peak used, then run Lambda Power Tuning for duration-sensitive functions. More memory also means more CPU, so test before cutting CPU-bound functions.
- **$/mo:** invocations/mo x avg duration s x (current GB - new GB) x $0.0000166667, if duration stays the same.

### B6. Stopped instances and old AMIs still holding storage
- **Check:** instances stopped for weeks (EBS still bills), and AMIs nobody launches.
- **Cmd:** `aws ec2 describe-instances --filters Name=instance-state-name,Values=stopped --query 'Reservations[].Instances[].[InstanceId,InstanceType,StateTransitionReason]' --output table`
- **Cmd:** `aws ec2 describe-images --owners self --query 'Images[].[ImageId,CreationDate,Name]' --output text | sort -k2 | head -50`
- **Fix:** snapshot then terminate long-stopped instances; deregister old AMIs and their snapshots (human).
- **$/mo:** attached EBS GB x volume price; AMI snapshot GB x $0.05.

### B7. Idle or oversized RDS
- **Check:** RDS instances with low CPU and few connections for 14 days, or Compute Optimizer "Overprovisioned"/idle.
- **IaC:** `grep -rnE 'instance_class|DBInstanceClass|instanceType.*db[.]' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Cmd:** `aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,Engine,MultiAZ,AllocatedStorage]' --output table`
- **Cmd:** `aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name CPUUtilization --dimensions Name=DBInstanceIdentifier,Value=my-db --start-time 2026-10-14T00:00:00Z --end-time 2026-10-28T00:00:00Z --period 86400 --statistics Average Maximum --output table`
- **Cmd:** `aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name DatabaseConnections --dimensions Name=DBInstanceIdentifier,Value=my-db --start-time 2026-10-14T00:00:00Z --end-time 2026-10-28T00:00:00Z --period 86400 --statistics Maximum --output table`
- **Cmd:** `aws compute-optimizer get-rds-database-recommendations --query 'rdsDBRecommendations[].[resourceArn,idle,instanceFinding,currentDBInstanceClass,instanceRecommendationOptions[0].dbInstanceClass,instanceRecommendationOptions[0].savingsOpportunity.estimatedMonthlySavings.value]' --output table`
- **Fix:** zero connections for 14 days = snapshot and delete (human). Max CPU under about 30% and freeable memory high = one class down in IaC. Multi-AZ off in non-prod.
- **$/mo:** (current class hourly - target hourly) x 730, doubled for Multi-AZ (e.g. db.r6g.xlarge $0.48/h to db.r6g.large $0.24/h = $175.20/mo Single-AZ).

### B8. Extended support fees (RDS and EKS)
- **Check:** RDS MySQL/PostgreSQL major versions past end of standard support, and EKS clusters on a Kubernetes version in extended support. Both bill a large surcharge automatically.
- **IaC:** `grep -rnE 'engine_version|EngineVersion|engine_lifecycle_support|cluster_version|kubernetes_version|upgrade_policy' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Cmd:** `aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,Engine,EngineVersion,EngineLifecycleSupport]' --output table`
- **Cmd:** `aws eks list-clusters --query 'clusters' --output text`
- **Cmd:** `aws eks describe-cluster --name my-cluster --query 'cluster.[name,version,upgradePolicy.supportType]' --output table`
- **Evidence:** A2 usage types containing `ExtendedSupport`.
- **Fix:** plan the major version upgrade (human, tested on a snapshot restore first). For new RDS, set `engine_lifecycle_support = "open-source-rds-extended-support-disabled"` so it cannot slip in silently.
- **$/mo:** RDS: vCPUs x $0.10/vCPU-h x 730 = $73 per vCPU (years 1 and 2; $0.20 in year 3), doubled for Multi-AZ. EKS: ($0.60 - $0.10)/h x 730 = $365 per cluster.

## C. Commitments: Savings Plans and Reserved Instances

### C1. Coverage and utilization
- **Check:** share of steady compute on Savings Plans or RIs, and whether existing ones are fully used or about to expire.
- **Cmd:** `aws ce get-savings-plans-coverage --time-period Start=2026-09-01,End=2026-10-01 --granularity MONTHLY --query 'SavingsPlansCoverages[].Coverage' --output table`
- **Cmd:** `aws ce get-savings-plans-utilization --time-period Start=2026-09-01,End=2026-10-01 --query 'Total.Utilization' --output table`
- **Cmd:** `aws ce get-reservation-coverage --time-period Start=2026-09-01,End=2026-10-01 --group-by Type=DIMENSION,Key=SERVICE --query 'Total.CoverageHours' --output table`
- **Cmd:** `aws savingsplans describe-savings-plans --query 'savingsPlans[].[savingsPlanType,commitment,end,state]' --output table`
- **Fix:** if steady on-demand compute is under about 70% covered, recommend a 1-year no-upfront Compute Savings Plan sized to the lowest hourly on-demand spend of the last 30 days. Rightsize first (B1, B2, B3), then commit. Purchases are for the human.
- **$/mo:** use AWS's own recommendation, it states its estimated monthly savings:
- **Cmd:** `aws ce get-savings-plans-purchase-recommendation --savings-plans-type COMPUTE_SP --term-in-years ONE_YEAR --payment-option NO_UPFRONT --lookback-period-in-days THIRTY_DAYS --query 'SavingsPlansPurchaseRecommendation.SavingsPlansPurchaseRecommendationSummary' --output json`
- Without it: covered on-demand $/mo x about 25% (1-year no-upfront Compute SP; RDS RIs about 30 to 40%). Mark as approximate.

## D. Network: NAT, data transfer, public IPv4

### D1. NAT Gateway processing
- **Check:** NAT gateways with no S3/DynamoDB gateway endpoints, and private-subnet Lambdas or tasks pushing S3, Secrets Manager, ECR or CloudWatch Logs traffic through NAT. One NAT per AZ in non-prod.
- **IaC:** `grep -rnE 'aws_nat_gateway|EC2::NatGateway|natGateways|aws_vpc_endpoint|vpc_endpoint' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .` (NAT present, no `service_name` for s3/dynamodb = finding)
- **Cmd:** `aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways[].[NatGatewayId,VpcId,SubnetId]' --output table`
- **Cmd:** `aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[].[VpcId,ServiceName,VpcEndpointType]' --output table`
- **Cmd:** `aws cloudwatch get-metric-statistics --namespace AWS/NATGateway --metric-name BytesInFromSource --dimensions Name=NatGatewayId,Value=nat-0123456789abcdef0 --start-time 2026-09-01T00:00:00Z --end-time 2026-10-01T00:00:00Z --period 2592000 --statistics Sum --output table`
- **Cmd:** `aws cloudwatch get-metric-statistics --namespace AWS/NATGateway --metric-name BytesInFromDestination --dimensions Name=NatGatewayId,Value=nat-0123456789abcdef0 --start-time 2026-09-01T00:00:00Z --end-time 2026-10-01T00:00:00Z --period 2592000 --statistics Sum --output table`
- Processed GB = (BytesInFromSource + BytesInFromDestination) / 1e9. Or use `NatGateway-Bytes` from A2.
- **Fix:** add free S3 and DynamoDB gateway endpoints; add interface endpoints for heavy services (ECR api+dkr, Secrets Manager, Logs, STS) where their traffic is large; one NAT (or none, public subnets plus IPv6) in non-prod.
- **$/mo:** NAT = $0.045/h x 730 = $32.85 per NAT + $0.045/GB processed. Gateway endpoint saves GB to S3/DynamoDB x $0.045. Interface endpoint costs $7.30 per AZ + $0.01/GB, so each GB moved off NAT saves $0.045 - $0.01 = $0.035 and the endpoint pays off above $7.30 / $0.035 = about 209 GB/mo per AZ. Removing a non-prod NAT saves $32.85 + its GB x $0.045.

### D2. Cross-AZ transfer
- **Check:** chatty traffic between AZs: app in one AZ, DB primary or cache in another, Lambdas spread across subnets in all AZs.
- **Evidence:** usage type `DataTransfer-Regional-Bytes` from A2 (it sits under EC2, not its own service).
- **IaC:** `grep -rnE 'availability_zone|subnet_ids|preferred_cache_cluster_azs|multi_az' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Fix:** keep the hot path in the DB primary's AZ (first Lambda subnet, cache node); recheck after a Multi-AZ failover moves the primary.
- **$/mo:** $0.01/GB is charged on the sending side and again on the receiving side, so each GB that crosses AZs one way costs $0.02. Request plus response doubles it again.

### D3. Internet egress
- **Check:** large `DataTransfer-Out-Bytes` from EC2, S3 or ALB serving static or media files directly.
- **Evidence:** A2 output rows ending `DataTransfer-Out-Bytes`.
- **Fix:** serve through CloudFront (or the existing CDN) with long cache headers; compress responses.
- **$/mo:** egress GB x ($0.09 - CloudFront rate, about $0.085) is small; the win is the cache hit ratio: GB x hit ratio x $0.09 off origin egress. Origin fetch from AWS origins (S3, ALB, EC2) to CloudFront is free, and CloudFront's always-free tier covers 1 TB/mo out, so a small site can drop egress to $0. The first 100 GB/mo out from AWS regions is also free across the account.

### D4. Public IPv4 addresses
- **Check:** every public IPv4 bills, attached or not. Unassociated Elastic IPs are pure waste.
- **IaC:** `grep -rnE 'aws_eip|associate_public_ip_address *= *true|map_public_ip_on_launch' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Cmd:** `aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].[PublicIp,AllocationId]' --output table`
- **Cmd:** `aws ec2 describe-network-interfaces --query 'NetworkInterfaces[?Association.PublicIp].[NetworkInterfaceId,InterfaceType,Association.PublicIp]' --output table`
- **Fix:** release unassociated EIPs (human); move instances behind a load balancer or into private subnets; drop `associate_public_ip_address`.
- **$/mo:** $0.005/h x 730 = $3.65 per address.

### D5. Idle load balancers
- **Check:** ALBs/NLBs with no healthy targets or near-zero requests.
- **Cmd:** `aws elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,Type,CreatedTime]' --output table`
- **Cmd:** `aws elbv2 describe-target-groups --query 'TargetGroups[].[TargetGroupName,LoadBalancerArns[0]]' --output text`
- **Cmd:** `aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name RequestCount --dimensions Name=LoadBalancer,Value=app/my-alb/0123456789abcdef --start-time 2026-10-14T00:00:00Z --end-time 2026-10-28T00:00:00Z --period 86400 --statistics Sum --output table`
- **Cmd:** `aws cloudwatch get-metric-statistics --namespace AWS/NetworkELB --metric-name ActiveFlowCount --dimensions Name=LoadBalancer,Value=net/my-nlb/0123456789abcdef --start-time 2026-10-14T00:00:00Z --end-time 2026-10-28T00:00:00Z --period 86400 --statistics Maximum --output table`
- Idle = near-zero daily RequestCount (ALB) or ActiveFlowCount (NLB) for 14 days. The `LoadBalancer` dimension is the ARN suffix after `loadbalancer/`.
- **Fix:** delete unused ones (human); share one ALB across services with host or path rules.
- **$/mo:** ALB $0.0225/h x 730 = $16.43 + LCUs; NLB the same base.

## E. Storage: EBS, snapshots, S3, ECR

### E1. gp2 to gp3
- **Check:** any gp2 EBS volume. RDS `gp2` storage is a performance item, not a saving (see below).
- **IaC:** `grep -rnE 'type *= *"gp2"|VolumeType: *gp2|storage_type *= *"gp2"|volumeType.*gp2' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Cmd:** `aws ec2 describe-volumes --filters Name=volume-type,Values=gp2 --query 'Volumes[].[VolumeId,Size,State]' --output table`
- **Cmd:** `aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,StorageType,AllocatedStorage,Iops]' --output text | grep gp2`
- **Fix:** change type to gp3 in IaC (online, no downtime). gp3 includes 3,000 IOPS and 125 MB/s; gp2 volumes over 1 TB had more baseline IOPS, so set gp3 IOPS to match.
- **$/mo:** EBS only: GB x ($0.10 - $0.08) = 20% of the gp2 GB-month cost. RDS gp2 and gp3 cost the same per GB ($0.115 Single-AZ), so moving RDS to gp3 is for baseline IOPS/throughput (3,000 IOPS and 125 MB/s under 400 GB) and lets you stop over-allocating storage just to get IOPS; count savings only if storage can shrink or io1 IOPS can be dropped.

### E2. Unattached EBS volumes
- **Check:** volumes in state `available`.
- **Cmd:** `aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].[VolumeId,Size,VolumeType,CreateTime]' --output table`
- **Fix:** snapshot if unsure, then delete (human).
- **$/mo:** GB x $0.08 (gp3) or $0.10 (gp2) or $0.125 (io1/io2, plus provisioned IOPS x $0.065).

### E3. Old snapshots
- **Check:** EBS and manual RDS snapshots older than the retention policy, or of deleted volumes.
- **IaC:** `grep -rnE 'aws_dlm_lifecycle_policy|aws_backup_plan|backup_retention_period|delete_after' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Cmd:** `aws ec2 describe-snapshots --owner-ids self --query 'Snapshots[].[StartTime,SnapshotId,VolumeSize,VolumeId]' --output text | sort | head -50`
- **Cmd:** `aws rds describe-db-snapshots --snapshot-type manual --query 'DBSnapshots[].[SnapshotCreateTime,DBSnapshotIdentifier,AllocatedStorage]' --output text | sort`
- **Fix:** Data Lifecycle Manager or AWS Backup with a retention rule; delete old ones (human); archive tier for long-term keeps.
- **$/mo:** snapshot GB x $0.05 (upper bound: snapshots are incremental, real stored GB is often lower; use `SnapshotUsage` from A2). Archive tier is $0.0125/GB. RDS manual snapshots: GB x about $0.095 (automated backups up to the DB's size are free; manual ones are not).

### E4. S3 lifecycle and Intelligent-Tiering
- **Check:** large buckets with no lifecycle rule, versioning on with no noncurrent-version expiry, incomplete multipart uploads, old build artifacts and backups kept forever.
- **IaC:** `grep -rnE 'aws_s3_bucket"|aws_s3_bucket_lifecycle_configuration|LifecycleConfiguration|INTELLIGENT_TIERING|noncurrent_version_expiration' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Cmd:** `aws s3api list-buckets --query 'Buckets[].Name' --output text`
- **Cmd:** `aws s3api get-bucket-lifecycle-configuration --bucket my-bucket`
- **Cmd:** `aws s3api get-bucket-versioning --bucket my-bucket`
- **Cmd:** `aws s3api list-multipart-uploads --bucket my-bucket --query 'Uploads[].[Initiated,Key]' --output text | head -20`
- **Cmd:** `aws cloudwatch get-metric-statistics --namespace AWS/S3 --metric-name BucketSizeBytes --dimensions Name=BucketName,Value=my-bucket Name=StorageType,Value=StandardStorage --start-time 2026-10-25T00:00:00Z --end-time 2026-10-28T00:00:00Z --period 86400 --statistics Average --output table`
- **Fix:** lifecycle rule: abort incomplete multipart after 7 days, expire noncurrent versions after 30 days, expire old hashed build assets after about 30 days (not sooner: open tabs still load old chunks), move backups to Glacier Instant Retrieval or Deep Archive. Intelligent-Tiering for large buckets with unknown access patterns and objects over 128 KB. Watch WAL/PITR archive buckets: they grow every day.
- **$/mo:** GB x (Standard $0.023 - target): Standard-IA $0.0125, Glacier IR $0.004, Deep Archive $0.00099. Intelligent-Tiering adds $0.0025 per 1,000 objects monitored; skip it for millions of tiny objects. Subtract one-time transition fees (per 1,000 objects: about $0.01 to IA, $0.02 to Glacier IR, $0.05 to Deep Archive). Minimum billed duration: IA 30 days, Glacier IR 90, Deep Archive 180; IA and Glacier IR bill objects under 128 KB as 128 KB, so small or short-lived objects can cost more after a transition.

### E5. ECR images kept forever
- **Check:** repositories with no lifecycle policy.
- **IaC:** `grep -rnE 'aws_ecr_repository|aws_ecr_lifecycle_policy|LifecyclePolicy' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Cmd:** `aws ecr describe-repositories --query 'repositories[].repositoryName' --output text`
- **Cmd:** `aws ecr get-lifecycle-policy --repository-name my-repo`
- **Fix:** keep the last 10 to 20 tagged images, expire untagged after 7 days.
- **$/mo:** stored GB x $0.10.

## F. Logs and monitoring

### F1. CloudWatch Logs retention
- **Check:** log groups with "Never expire", especially Lambda groups auto-created on first run and groups for deleted functions.
- **IaC:** `grep -rnE 'aws_cloudwatch_log_group|retention_in_days|RetentionInDays|logRetention' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .` (an `aws_lambda_function` with no matching `aws_cloudwatch_log_group` = finding)
- **Cmd:** `aws logs describe-log-groups --query 'logGroups[?!retentionInDays].[storedBytes,logGroupName]' --output text | sort -rn | head -30`
- **Fix:** create the log group in IaC with `retention_in_days` (14 to 30 for app logs, longer only for audit) before the function first runs; delete groups of deleted functions (human).
- **$/mo:** stored GB x $0.03 for what retention would drop.

### F2. Log ingestion volume
- **Check:** groups ingesting the most GB (DEBUG logging in prod, per-request dumps). Ingestion usually costs more than storage.
- **Evidence:** A2 usage type `DataProcessing-Bytes` under CloudWatch.
- **Cmd:** `aws cloudwatch get-metric-statistics --namespace AWS/Logs --metric-name IncomingBytes --dimensions Name=LogGroupName,Value=/aws/lambda/my-fn --start-time 2026-09-01T00:00:00Z --end-time 2026-10-01T00:00:00Z --period 2592000 --statistics Sum --output table`
- **Fix:** set log level to INFO or WARN in prod; sample noisy logs; Infrequent Access log class for logs only kept for audit.
- **$/mo:** ingested GB cut x $0.50 (Infrequent Access class: $0.25).

### F3. Metered read APIs and pollers
- **Check:** code or crons calling paid APIs in loops: Cost Explorer `GetCostAndUsage` ($0.01 each), `GetMetricData` ($0.01 per 1,000 metrics), Logs Insights ($0.005/GB scanned), AWS Config recording every resource change ($0.003 per item). Two uptime pollers watching the same endpoints.
- **IaC:** `grep -rnE 'GetCostAndUsage|getCostAndUsage|get_cost_and_usage|GetMetricData|StartQuery|schedule_expression|rate[(]' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Cmd:** `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=GetCostAndUsage --max-results 50 --query 'Events[].[EventTime,Username]' --output text | cut -f2 | sort | uniq -c`
- **Cmd:** `aws configservice describe-configuration-recorders --output json`
- **Fix:** pull itemised cost once a day; use the free `AWS/Billing EstimatedCharges` metric for hourly checks; record Config only for resource types you audit; keep one uptime source of truth.
- **$/mo:** calls/day x 30 x unit price.

## G. Guardrails

### G1. Cost allocation tags
- **Check:** resources missing team, environment or service tags; tags not activated for billing. Without them, per-service or per-run cost cannot be split out of account-wide totals.
- **IaC:** `grep -rnE 'default_tags|Tags:|tags *=' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Cmd:** `aws ce list-cost-allocation-tags --status Active --query 'CostAllocationTags[].TagKey' --output text`
- **Fix:** `default_tags` in the Terraform provider (or CDK `Tags.of(app)`), then activate the keys in Billing. Use a separate account for experiments.
- **$/mo:** n/a (enables every other estimate).

### G2. Budgets and anomaly alerts
- **Check:** no AWS Budget, no Cost Anomaly Detection monitor.
- **IaC:** `grep -rnE 'aws_budgets_budget|aws_ce_anomaly_monitor|::Budgets' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude-dir=cdk.out --exclude='*.tfstate*' .`
- **Cmd:** `aws budgets describe-budgets --account-id 123456789012 --query 'Budgets[].[BudgetName,BudgetLimit.Amount,TimeUnit]' --output table`
- **Cmd:** `aws ce get-anomaly-monitors --query 'AnomalyMonitors[].[MonitorName,MonitorType]' --output table`
- **Fix:** a monthly budget at about 110% of the normal bill with 80% and 100% alerts; a service-level anomaly monitor. For a custom alert, flag a day only when it is above mean + 3 sigma AND up 20% AND up $50, so small accounts stay quiet.
- **$/mo:** n/a (risk). Budgets cost little or nothing (a free allowance, then cents per budget per day; check current pricing).

### G3. Disposable and decommissioned resources
- **Check:** test servers with no cleanup deadline; old hosts kept after a migration (instances, static IPs, key pairs, old DBs). Check every enabled region (A4), not only the main one.
- **Cmd:** `aws ec2 describe-regions --query 'Regions[].RegionName' --output text`
- **Fix:** tag test resources with an owner and expiry; after DNS cutover keep the old host about 48h as rollback and the old DB until a restore is verified, then terminate and release IPs (human).
- **$/mo:** sum of the leftover resources at the prices above.

### G4. Cost estimates for new products
- **Check:** pricing or quotas based on event counts instead of retained bytes; estimates taken from a quiet environment.
- **Fix:** model storage from retained bytes (e.g. 2M events/mo x 365-day retention x 32 KiB is about 732 GiB vs 46 GiB at 2 KiB); treat a quiet-week sample as a floor that leaves out peaks, backups, support and payment fees.
- **$/mo:** show the formula with the user's numbers.
