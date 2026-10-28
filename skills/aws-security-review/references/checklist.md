# AWS security checklist

Work through every section. For each item, record a finding, a pass, or "inconclusive" with the
reason (no access, no IaC, region not checked). A check you could not run is never a pass.

Repo greps come in two forms. Patterns are single-quoted, with no backslashes and no `$`.

- Config patterns (ports, flags, resource types): `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude='*.tfstate*' 'PATTERN' .`
- Secret-bearing patterns (keys, passwords, tokens, URLs with credentials): print the location
  only, never the matched text:
  `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude='*.tfstate*' 'PATTERN' . | cut -d: -f1,2`.
  Do not open the file to look at the value. Report file:line and "value masked".

Placeholders in commands are UPPER_CASE (`USER_NAME`, `BUCKET_NAME`). Replace them with real
values from earlier output. Every command here is a single read-only call that passes the guard.
Prefer `--profile NAME` and `--region REGION` flags over env prefixes. Regional services
(GuardDuty, Config, Security Hub, Access Analyzer, EC2, RDS) must be checked in every region in
use: `aws ec2 describe-regions --query 'Regions[].RegionName' --output text`.

Never print a secret value. Commands below return names, flags and dates only. If output does
contain a secret anyway, stop quoting it: report its location (file:line or resource and field)
with the value masked, for example `AKIA************WXYZ`.

## 1. Root account and account setup

### 1.1 Root has MFA and no access keys
- **Check:** root MFA is on; root has no access keys.
- **Evidence:** `aws iam get-account-summary --query 'SummaryMap.{RootMFA:AccountMFAEnabled,RootKeys:AccountAccessKeysPresent}'`
- **Why:** in a standalone account nothing limits root. In an org, SCPs bind member-account root
  but never the management account. A leaked root key is full account takeover.
- **Fix:** human deletes root keys and enables hardware or passkey MFA in the console.
- **Est. $/mo:** n/a. Risk: full account compromise.

### 1.2 Root is not used day to day
- **Check:** no recent root sign-ins or API calls.
- **Evidence:** `aws cloudtrail lookup-events --region us-east-1 --lookup-attributes AttributeKey=Username,AttributeValue=root --max-results 20 --query 'Events[].[EventTime,EventName]' --output text`
  (console sign-ins and other global events land in us-east-1; repeat with `--region REGION` for
  regional API calls). Event history covers only the last 90 days; no hits is not proof of no use.
  Export to ask for: the IAM credential report CSV (`password_last_used`, `access_key_1_last_used_date` for `<root_account>`).
- **Why:** root use means no per-person audit trail and no least privilege.
- **Fix:** move people to IAM Identity Center; add an EventBridge rule or metric filter alarm on root sign-in.
- **Est. $/mo:** n/a. Risk: untraceable, unrestricted actions.

### 1.3 Security contact and org guardrails
- **Check:** a security alternate contact is set; in an org, SCPs deny leaving the org, disabling
  CloudTrail/GuardDuty/Config, and unused regions.
- **Evidence:** `aws account get-alternate-contact --alternate-contact-type SECURITY`;
  `aws organizations list-policies --filter SERVICE_CONTROL_POLICY --query 'Policies[].Name' --output text`
- **Why:** AWS abuse and compromise notices go to the contact. SCPs bind every principal in
  member accounts, admins and root included, but not the management account, so keep workloads
  out of it.
- **Fix:** set the contact; add a baseline SCP (Terraform `aws_organizations_policy`).
- **Est. $/mo:** n/a. Risk: missed AWS compromise notices.

## 2. IAM identities and policies

### 2.1 Humans use SSO, not IAM users with keys
- **Check:** count IAM users, their console use and key age. Keys older than 90 days or unused
  for 45 days are findings.
- **Evidence:** `aws iam list-users --query 'Users[].[UserName,CreateDate,PasswordLastUsed]' --output text`;
  `aws iam list-access-keys --user-name USER_NAME --query 'AccessKeyMetadata[].[Status,CreateDate]' --output text`;
  `aws iam get-access-key-last-used --access-key-id ACCESS_KEY_ID --query 'AccessKeyLastUsed.[LastUsedDate,ServiceName]' --output text`.
  Export: IAM credential report CSV. IaC: `aws_iam_access_key`, `IAM::AccessKey` (CloudFormation).
- **Why:** long-lived keys are the most common AWS breach path (leaked in repos, laptops, CI logs).
- **Fix:** IAM Identity Center for people, roles for workloads, delete unused keys, rotate the rest.
  In reports, mask key IDs to the last 4 characters.
- **Est. $/mo:** n/a. Risk: credential compromise.

### 2.1b IAM users with console access have MFA; a password policy exists
- **Check:** every user with a login profile has an MFA device; the account password policy
  requires length 14+ and no reuse (CIS).
- **Evidence:** `aws iam get-login-profile --user-name USER_NAME` (NoSuchEntity means no console
  password); `aws iam list-mfa-devices --user-name USER_NAME --query 'MFADevices[].[SerialNumber,EnableDate]' --output text`;
  `aws iam get-account-password-policy` (NoSuchEntity means no policy). Export: credential report
  columns `password_enabled` and `mfa_active`.
- **Why:** a console password without MFA falls to phishing or reuse.
- **Fix:** enforce MFA (or move the user to Identity Center); `aws_iam_account_password_policy`.
- **Est. $/mo:** n/a. Risk: console account takeover.

### 2.2 No wildcard or admin policies
- **Check:** Allow statements with `Action: "*"`, `NotAction`, or `service:*` on `Resource: "*"`,
  in customer managed policies and inline user, group and role policies; `Resource: "*"` on
  data services (S3, SES, Secrets Manager, KMS, DynamoDB); who holds AdministratorAccess.
- **Evidence:** IaC grep: `"Action": "[*]"`, `actions *= *[[] *"[*]"`, `NotAction|not_actions`,
  `"[a-z0-9-]+:[*]"`, `Resource.*"[*]"`.
  Live (`--filter` keeps AWS-managed policies such as AdministratorAccess out of `.Policies`;
  they are covered by the `list-entities-for-policy` call below): `aws iam get-account-authorization-details --filter User Group Role LocalManagedPolicy --output json | jq -r 'def l: if type == "array" then . else [.] end; [(.Policies[] | {n: ("policy " + .PolicyName), s: [.PolicyVersionList[] | select(.IsDefaultVersion) | .Document.Statement]}), (.UserDetailList[] | {n: ("user " + .UserName), s: [.UserPolicyList[]?.PolicyDocument.Statement]}), (.GroupDetailList[] | {n: ("group " + .GroupName), s: [.GroupPolicyList[]?.PolicyDocument.Statement]}), (.RoleDetailList[] | {n: ("role " + .RoleName), s: [.RolePolicyList[]?.PolicyDocument.Statement]})][] | select([.s[] | l[] | select(.Effect == "Allow") | has("NotAction") or ((.Action // [] | l | index("*")) != null) or ((.Action // [] | l | map(test(":[*]")) | any) and ((.Resource // [] | l | index("*")) != null))] | any) | .n'`;
  `aws iam list-entities-for-policy --policy-arn arn:aws:iam::aws:policy/AdministratorAccess`.
  Limit: the filter ignores Conditions, `NotResource`, permissions boundaries and SCPs, and
  does not flag `s3:Get*`-style partial wildcards. Always pair it with the IaC grep and Access
  Analyzer (2.7); treat a clean result as "nothing found by this filter".
- **Why:** AI-written and copied IAM drifts to `*:*`; one compromised workload then owns the account.
- **Fix:** scope each role to one bucket, one SES identity ARN, `secret:PREFIX/*`. Gate IAM in CI
  with a lint that fails on `*`+`*`, `iam:*`, user-attached policies and AssumeRole Allow with no
  Condition, plus Checkov.
- **Est. $/mo:** n/a. Risk: privilege escalation to admin.

### 2.3 Policies attach to roles or groups, not users
- **Check:** users with attached or inline policies.
- **Evidence:** `aws iam get-account-authorization-details --filter User --output json | jq -r '.UserDetailList[] | [.UserName, (.AttachedManagedPolicies | length), (.UserPolicyList // [] | length)] | @tsv'`.
  IaC: `aws_iam_user_policy`, `aws_iam_user_policy_attachment`.
- **Why:** user policies are hard to audit and survive offboarding.
- **Fix:** move to groups or Identity Center permission sets.
- **Est. $/mo:** n/a. Risk: stale access.

### 2.4 Cross-account roles require ExternalId and trust one principal
- **Check:** roles trusted by another account have an `sts:ExternalId` condition, trust a
  specific role ARN (not `:root`), and `MaxSessionDuration` is 3600.
- **Evidence:** `aws iam list-roles --output json | jq -r '.Roles[] | select(.AssumeRolePolicyDocument | tostring | test("iam::[0-9]+:")) | [.RoleName, .MaxSessionDuration, (.AssumeRolePolicyDocument | tostring | contains("sts:ExternalId"))] | @tsv'`;
  `aws iam get-role --role-name ROLE_NAME --query Role.AssumeRolePolicyDocument`
  Wildcard principal (anyone can assume): `aws iam list-roles --output json | jq -r '.Roles[] | select([.AssumeRolePolicyDocument.Statement | if type == "array" then .[] else . end | select(.Effect == "Allow") | .Principal | . == "*" or ((.AWS? // []) | if type == "array" then index("*") != null else . == "*" end)] | any) | .RoleName'`.
  A hit is Critical unless a Condition (for example `aws:PrincipalOrgID`) narrows it; then High.
- **Why:** without ExternalId any customer of the same vendor can make the vendor assume your
  role (confused deputy). A `*` principal lets any AWS account assume it.
- **Fix:** add `Condition.StringEquals.sts:ExternalId` with a vendor-generated UUID; set the
  principal to the vendor's role ARN; `max_session_duration = 3600`.
- **Est. $/mo:** n/a. Risk: third-party read or write into the account.

### 2.5 Third-party roles are not "read-only" with data access
- **Check:** vendor or monitoring roles with `ReadOnlyAccess` attached.
- **Evidence:** `aws iam list-entities-for-policy --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess --entity-filter Role`
- **Why:** ReadOnlyAccess reads S3 objects, SSM parameter values, SQS messages, DynamoDB items
  and Lambda env vars, and AWS changes it silently.
- **Fix:** use `ViewOnlyAccess` or an explicit Describe/List/Get allowlist plus an explicit Deny
  on `s3:GetObject`, `ssm:GetParameter*`, `secretsmanager:GetSecretValue`, `kms:Decrypt`,
  `sqs:ReceiveMessage`, `dynamodb:GetItem/Query/Scan`, `ec2:GetPasswordData`, `ec2:GetConsoleOutput`.
- **Est. $/mo:** n/a. Risk: vendor breach exposes your data.

### 2.6 CI uses OIDC, not stored keys
- **Check:** GitHub OIDC role trust pins `sub` to one repo and branch and `aud` to
  `sts.amazonaws.com`; no AWS keys in CI secrets.
- **Evidence:** IaC grep (config form): `token.actions.githubusercontent.com:sub.*[*]`.
  Stored keys (location-only form, the line may hold a literal key):
  `grep -rniE 'AWS.ACCESS.KEY.ID|AWS.SECRET.ACCESS.KEY' .github | cut -d: -f1,2`.
  A `secrets.NAME` reference is a stored CI secret; a literal value is also a leaked key. Live:
  `aws iam list-roles --output json | jq -r '.Roles[] | select(.AssumeRolePolicyDocument | tostring | contains("token.actions.githubusercontent.com")) | .RoleName'`;
  `gh secret list` (names only).
- **Why:** a wildcard `sub` lets any repo or fork branch assume the deploy role; stored keys leak.
- **Fix:** `StringEquals` on `sub = repo:ORG/REPO:ref:refs/heads/main`; thumbprint from a
  `tls_certificate` data source; delete the stored keys.
- **Est. $/mo:** n/a. Risk: deploy-role takeover.

### 2.7 Access Analyzer is on and clean
- **Check:** an external access analyzer exists per region; no active findings.
- **Evidence:** `aws accessanalyzer list-analyzers --query 'analyzers[].[name,type,status]' --output text`;
  `aws accessanalyzer list-findings-v2 --analyzer-arn ANALYZER_ARN --filter '{"status":{"eq":["ACTIVE"]}}' --query 'findings[].[resourceType,resource]' --output text`
- **Why:** it finds buckets, keys, roles, queues and functions shared outside the account.
- **Fix:** create an account or org analyzer (`aws_accessanalyzer_analyzer`).
- **Est. $/mo:** external access analyzer is free. Risk: unknown public sharing.

## 3. Network exposure

### 3.1 No admin or database ports open to the internet
- **Check:** ingress from `0.0.0.0/0` or `::/0` on 22, 3389, 3306, 5432, 1433, 6379, 9200,
  27017, 11211, or all ports (`-1`).
- **Evidence:** `aws ec2 describe-security-group-rules --output json | jq -r '.SecurityGroupRules[] | select(.IsEgress | not) | select(.CidrIpv4 == "0.0.0.0/0" or .CidrIpv6 == "::/0") | [.GroupId, .IpProtocol, .FromPort, .ToPort] | @tsv'`.
  IaC grep: `cidr_blocks *= *[[]"0.0.0.0/0"` near `from_port *= *22`, `CidrIp: 0.0.0.0/0`;
  comments like "change for production".
- **Why:** open SSH/RDP/DB ports are brute-forced within minutes of launch.
- **Fix:** remove the rule; use SSM Session Manager or an operator IP `/32`; DBs only from the app SG.
- **Est. $/mo:** n/a. Risk: direct compromise of hosts or data.

### 3.2 Default security groups are empty; egress is scoped where it matters
- **Check:** default SGs have no rules (CIS); DB and worker SGs do not allow all egress.
- **Evidence:** `aws ec2 describe-security-groups --filters Name=group-name,Values=default --query 'SecurityGroups[].[GroupId,VpcId,length(IpPermissions),length(IpPermissionsEgress)]' --output text`
- **Why:** resources dropped into the default SG inherit its access; open egress eases exfiltration.
- **Fix:** strip default SG rules (`aws_default_security_group` with no blocks).
- **Est. $/mo:** n/a. Risk: lateral movement, exfiltration.

### 3.3 Instances have no public IP unless intended
- **Check:** instances with public IPs; subnets that auto-assign them.
- **Evidence:** `aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,PublicIpAddress,SubnetId]' --output text`;
  `aws ec2 describe-subnets --query 'Subnets[?MapPublicIpOnLaunch].[SubnetId,VpcId]' --output text`.
  IaC: `associate_public_ip_address = true`, `map_public_ip_on_launch = true`.
- **Why:** every public IP is attack surface; admin gateways should bind to loopback.
- **Fix:** private subnets behind a load balancer; attach an Elastic IP deliberately when needed.
- **Est. $/mo:** each public IPv4 costs about 3.65 (0.005 x 730 h). Risk: exposed services.

### 3.4 VPC flow logs and load balancer TLS
- **Check:** each VPC has flow logs; internet-facing listeners use HTTPS with a current TLS policy
  and HTTP only redirects.
- **Evidence:** `aws ec2 describe-flow-logs --query 'FlowLogs[].[ResourceId,TrafficType,LogDestinationType]' --output text`;
  `aws elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,Scheme,DNSName]' --output text`;
  `aws elbv2 describe-listeners --load-balancer-arn LB_ARN --query 'Listeners[].[Port,Protocol,SslPolicy]' --output text`
- **Why:** without flow logs there is no network evidence after an incident.
- **Fix:** `aws_flow_log` to S3 (cheaper than CloudWatch); `ELBSecurityPolicy-TLS13-1-2-2021-06`.
- **Est. $/mo:** flow logs to S3 about 0.25/GB delivered. Risk: blind incident response.

### 3.5 EKS API endpoint is not open to the world
- **Evidence:** `aws eks describe-cluster --name CLUSTER_NAME --query 'cluster.resourcesVpcConfig.[endpointPublicAccess,publicAccessCidrs]'`
- **Why / Fix:** a public endpoint on `0.0.0.0/0` exposes the control plane; restrict CIDRs or go private.
- **Est. $/mo:** n/a. Risk: cluster takeover via leaked kubeconfig.

## 4. Public data: S3, RDS, snapshots, images

### 4.1 S3 Block Public Access at account and bucket level
- **Evidence:** `aws s3control get-public-access-block --account-id ACCOUNT_ID`;
  `aws s3api list-buckets --query 'Buckets[].Name' --output text`;
  `aws s3api get-public-access-block --bucket BUCKET_NAME`;
  `aws s3api get-bucket-policy-status --bucket BUCKET_NAME`;
  `aws s3api get-bucket-policy --bucket BUCKET_NAME --query Policy --output text | jq .Statement`.
  IaC: `acl = "public-read"`, `Principal: "*"` with no Condition, `block_public_acls = false`.
- **Why:** public buckets are the classic AWS data leak.
- **Fix:** account-level BPA on; serve public files through CloudFront with OAC; grant
  `s3:GetObject` on exact keys only when a bucket must be public.
- **Est. $/mo:** n/a. Risk: data breach.

### 4.2 No secrets or config files in buckets
- **Check:** buckets used to ship `.env`, SSH keys or TLS private keys to CI or servers.
- **Evidence:** `aws s3 ls s3://BUCKET_NAME --recursive | grep -iE '[.]env|[.]pem|[.]key|id_rsa|credentials' | head -n 50`
  (object names only; never download the objects).
- **Why:** anyone with bucket read gets every credential.
- **Fix:** platform-managed variables, CI environment secrets, Secrets Manager; rotate what was stored.
- **Est. $/mo:** n/a. Risk: credential compromise.

### 4.3 Buckets enforce TLS; sensitive buckets use SSE-KMS
- **Check:** S3 encrypts every new object with SSE-S3 by default since January 2023, so "no
  encryption" is not a finding on its own. Flag: buckets holding regulated or customer data
  without SSE-KMS where policy or compliance needs key control, and buckets without a TLS-only
  Deny (CIS).
- **Evidence:** `aws s3api get-bucket-encryption --bucket BUCKET_NAME --query 'ServerSideEncryptionConfiguration.Rules[].[ApplyServerSideEncryptionByDefault.SSEAlgorithm,BucketKeyEnabled]' --output text`;
  `aws s3api get-bucket-policy --bucket BUCKET_NAME --query Policy --output text | jq -r '[.Statement | if type == "array" then .[] else . end | select(.Effect == "Deny") | tostring | contains("SecureTransport")] | any'`
  (`false` or NoSuchBucketPolicy means no TLS-only deny). IaC: no `SecureTransport` Deny.
- **Fix:** add the TLS-only Deny statement; SSE-KMS with a customer key and Bucket Keys where
  key control or separate decrypt permission is required.
- **Est. $/mo:** KMS key 1.00 each plus requests (Bucket Keys cut request cost). Risk: plaintext in
  transit; no separate decrypt control on sensitive data.

### 4.4 RDS and Aurora are private and encrypted
- **Evidence:** `aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,PubliclyAccessible,StorageEncrypted,DeletionProtection,IAMDatabaseAuthenticationEnabled]' --output text`;
  `aws rds describe-db-clusters --query 'DBClusters[].[DBClusterIdentifier,StorageEncrypted,DeletionProtection]' --output text`;
  `aws rds describe-db-parameters --db-parameter-group-name PARAM_GROUP --output json | jq -r '.Parameters[] | select(.ParameterName == "rds.force_ssl" or .ParameterName == "require_secure_transport") | [.ParameterName, .ParameterValue] | @tsv'`;
  Aurora sets TLS in the cluster parameter group:
  `aws rds describe-db-cluster-parameters --db-cluster-parameter-group-name CLUSTER_PARAM_GROUP --output json | jq -r '.Parameters[] | select(.ParameterName == "rds.force_ssl" or .ParameterName == "require_secure_transport") | [.ParameterName, .ParameterValue] | @tsv'`
  (`rds.force_ssl` for PostgreSQL, `require_secure_transport` for MySQL; missing or 0/OFF is a finding).
  IaC: `publicly_accessible = true`, `storage_encrypted` missing.
- **Why:** a public DB is one weak password from a breach; encryption cannot be added in place.
- **Fix:** private subnets, SG from the app only, force TLS; encrypt via snapshot copy and restore.
- **Est. $/mo:** n/a. Risk: data breach.

### 4.5 No public snapshots or AMIs
- **Evidence:** `aws ec2 describe-snapshots --owner-ids self --restorable-by-user-ids all --query 'Snapshots[].SnapshotId' --output text`;
  `aws ec2 get-snapshot-block-public-access-state`;
  `aws ec2 describe-images --owners self --query 'Images[?Public].ImageId' --output text`;
  `aws ec2 get-image-block-public-access-state`;
  `aws rds describe-db-snapshots --snapshot-type manual --query 'DBSnapshots[].[DBSnapshotIdentifier,Encrypted]' --output text`;
  `aws rds describe-db-snapshot-attributes --db-snapshot-identifier SNAPSHOT_ID --query 'DBSnapshotAttributesResult.DBSnapshotAttributes[].AttributeValues'` (`all` means public);
  Aurora: `aws rds describe-db-cluster-snapshots --snapshot-type manual --query 'DBClusterSnapshots[].[DBClusterSnapshotIdentifier,StorageEncrypted]' --output text`;
  `aws rds describe-db-cluster-snapshot-attributes --db-cluster-snapshot-identifier CLUSTER_SNAPSHOT_ID --query 'DBClusterSnapshotAttributesResult.DBClusterSnapshotAttributes[].AttributeValues'`.
- **Why:** a public snapshot is a full copy of the disk or database.
- **Fix:** remove `all` from restore attributes; turn on block public access for snapshots and AMIs.
- **Est. $/mo:** n/a. Risk: full data copy exposed.

### 4.6 Other resource policies are not public
- **Check:** Lambda function URLs with `AuthType NONE`, and SQS, SNS, ECR, KMS or Lambda policies
  with `Principal: "*"` and no Condition. Access Analyzer (2.7) covers most of these.
- **Evidence:** `aws lambda list-function-url-configs --function-name FUNCTION_NAME --query 'FunctionUrlConfigs[].[FunctionUrl,AuthType]' --output text`;
  `aws lambda get-policy --function-name FUNCTION_NAME --query Policy --output text | jq .Statement`
- **Fix:** `AWS_IAM` auth, or put the URL behind CloudFront with OAC; add `aws:SourceAccount`/`aws:SourceArn` conditions.
- **Est. $/mo:** n/a. Risk: unauthenticated invocation or data access.

## 5. Encryption at rest and keys

### 5.1 EBS, caches and queues encrypted
- **Evidence:** `aws ec2 get-ebs-encryption-by-default`;
  `aws ec2 describe-volumes --filters Name=encrypted,Values=false --query 'Volumes[].VolumeId' --output text`;
  `aws elasticache describe-replication-groups --query 'ReplicationGroups[].[ReplicationGroupId,AtRestEncryptionEnabled,TransitEncryptionEnabled,AuthTokenEnabled]' --output text`.
  IaC: Checkov (`checkov -d . --compact`) and grep for `encrypted`, `kms_key_id`. Copied tutorial
  code often omits the encryption block.
- **Fix:** turn on EBS default encryption per region; encryption and AUTH on Redis.
- **Est. $/mo:** n/a with AWS-managed keys. Risk: data readable from snapshots or backups.

### 5.2 KMS customer keys rotate and have tight key policies
- **Evidence:** `aws kms list-aliases --query 'Aliases[].[AliasName,TargetKeyId]' --output text`;
  `aws kms get-key-rotation-status --key-id KEY_ID`;
  `aws kms get-key-policy --key-id KEY_ID --policy-name default --output text | jq .Statement`
- **Why:** a key policy granting `kms:*` to `*` makes the encryption meaningless.
- **Fix:** `enable_key_rotation = true`; key admins separate from key users.
- **Est. $/mo:** 1.00 per customer key. Risk: weak data protection.

## 6. Secrets

### 6.1 No secrets in env vars, user data or IaC
- **Check:** plaintext secrets in Lambda/ECS environment, EC2 `user_data`, Terraform variables and state.
- **Evidence:** repo greps, location-only form only (these lines hold the secret):
  `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude='*.tfstate*' 'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}' . | cut -d: -f1,2`;
  `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform --exclude='*.tfstate*' 'user_data.*(password|secret|token)|(PASSWORD|SECRET|TOKEN|API_KEY) *[:=] *[A-Za-z0-9/+]{12,}' . | cut -d: -f1,2`.
  Committed state or env files, by name only (never open them): `git ls-files | grep -iE 'tfstate|[.]env'`.
  The guard blocks env-var reads, so ask the human to run these names-only reads (Commands for you to run):
  `aws lambda get-function-configuration --function-name FUNCTION_NAME --query 'keys(Environment.Variables)'`
  (an error on a function with no env vars means none; move on);
  `aws ecs describe-task-definition --task-definition TASK_DEF --query 'taskDefinition.containerDefinitions[].{name:name,env:environment[].name,secrets:secrets[].name}'`.
  User data is base64; ask the human to decode and check it (Commands for you to run).
- **Why:** env vars and user data are readable by anyone with Describe/Get on the resource,
  land in Terraform state, and show in instance metadata.
- **Fix:** Secrets Manager or SSM SecureString, referenced via ECS `secrets` or fetched at runtime;
  mark Terraform vars `sensitive`; encrypt and restrict the state bucket.
- **Est. $/mo:** Secrets Manager 0.40 per secret. Risk: credential compromise.

### 6.2 Secrets rotate and are stored as secrets
- **Evidence:** `aws secretsmanager list-secrets --query 'SecretList[].[Name,RotationEnabled,LastRotatedDate,LastAccessedDate]' --output text`;
  `aws ssm describe-parameters --query 'Parameters[].[Name,Type]' --output text` (`String` holding a credential is a finding).
- **Why:** after a provider breach or DB restore every stored secret counts as exposed; a restore
  can bring back revoked keys.
- **Fix:** rotation on; dual-password rotation for DBs; scoped API tokens over global account keys.
- **Est. $/mo:** n/a. Risk: long-lived exposure after a leak.

### 6.3 Git history and logs are clean
- **Evidence:** `gitleaks git --redact --no-banner .` (history; gitleaks before 8.19 uses
  `gitleaks detect --redact --no-banner`) and `gitleaks dir --redact --no-banner .` (working tree).
  Always `--redact`. Grep code for logging of config, env, request bodies or provider error text.
- **Why:** a secret in history stays valid until rotated; debug prints of config leak `DATABASE_URL`.
- **Fix:** rotate first, then purge; ban print of secret-holding config; test that the pre-commit
  secret hook actually fails on a planted secret.
- **Est. $/mo:** n/a. Risk: credential compromise.

## 7. Detection and logging

### 7.1 CloudTrail on in all regions, validated, protected
- **Evidence:** `aws cloudtrail describe-trails --query 'trailList[].[Name,IsMultiRegionTrail,LogFileValidationEnabled,KmsKeyId,S3BucketName]' --output text`;
  `aws cloudtrail get-trail-status --name TRAIL_NAME --query IsLogging`;
  `aws cloudtrail get-event-selectors --trail-name TRAIL_NAME`;
  trail bucket: `aws s3api get-bucket-policy-status --bucket TRAIL_BUCKET`;
  `aws s3api get-bucket-policy --bucket TRAIL_BUCKET --query Policy --output text | jq .Statement`
  (only the CloudTrail service principal may write; no `*` principal).
- **Why:** no trail means no answer to "who did this". The trail bucket must not be public or
  writable by workloads.
- **Fix:** one org or multi-region trail, log validation, KMS, Object Lock or a separate log account.
- **Est. $/mo:** first management trail free; data events 0.10 per 100k. Risk: no forensics.

### 7.2 GuardDuty, Config and Security Hub enabled
- **Evidence (per region):** `aws guardduty list-detectors`;
  `aws guardduty get-detector --detector-id DETECTOR_ID --query '[Status,Features[].[Name,Status]]'`;
  `aws guardduty list-findings --detector-id DETECTOR_ID --finding-criteria '{"Criterion":{"severity":{"Gte":7}}}'`;
  `aws guardduty get-findings --detector-id DETECTOR_ID --finding-ids FINDING_ID --query 'Findings[].[Severity,Type,Resource.ResourceType,UpdatedAt]' --output text`;
  `aws configservice describe-configuration-recorder-status --query 'ConfigurationRecordersStatus[].[name,recording,lastStatus]' --output text`;
  `aws securityhub get-enabled-standards --query 'StandardsSubscriptions[].[StandardsArn,StandardsStatus]' --output text`;
  `aws securityhub get-findings --filters '{"SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"}],"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}' --max-items 50 --query 'Findings[].[Title,Resources[0].Id]' --output text`.
  Export: Security Hub or Trusted Advisor findings CSV.
- **Why:** GuardDuty catches key misuse and crypto mining; Config proves state over time.
- **Fix:** enable in every region (delegated admin in an org); FSBP and CIS standards.
- **Est. $/mo:** usage-based; read the per-service estimate from the GuardDuty and Config usage pages, never guess.
  Risk: compromise goes unnoticed.

### 7.3 Alerts on root use and security changes
- **Evidence:** `aws logs describe-metric-filters --query 'metricFilters[].[filterName,filterPattern]' --output text`;
  `aws events list-rules --query 'Rules[].[Name,EventPattern]' --output text`
- **Fix:** EventBridge rules to SNS for root sign-in, IAM policy changes, CloudTrail stop, SG changes.
- **Est. $/mo:** under 1. Risk: slow detection.

## 8. Compute

### 8.1 IMDSv2 required
- **Evidence:** `aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,MetadataOptions.HttpTokens,MetadataOptions.HttpPutResponseHopLimit]' --output text`;
  `aws ec2 get-instance-metadata-defaults`. Launch templates (Commands for you to run: the guard
  blocks them because they include UserData; keep a `--query` that leaves out UserData):
  `aws ec2 describe-launch-template-versions --launch-template-id LT_ID --query 'LaunchTemplateVersions[].[VersionNumber,LaunchTemplateData.MetadataOptions.HttpTokens]' --output text`.
  IaC: missing `metadata_options { http_tokens = "required" }`.
- **Why:** with IMDSv1, one SSRF bug in the app hands out the instance role credentials.
- **Fix:** `http_tokens = "required"`, hop limit 1 (2 for containers); set the account-level
  IMDS default to IMDSv2 (a write: list it under Commands for you to run).
- **Est. $/mo:** n/a. Risk: credential theft via SSRF.

### 8.2 Hosts are managed, patched and key-only
- **Evidence:** `aws ssm describe-instance-information --query 'InstanceInformationList[].[InstanceId,PingStatus,PlatformName]' --output text`;
  `aws ecr describe-repositories --query 'repositories[].[repositoryName,imageScanningConfiguration.scanOnPush,imageTagMutability]' --output text`.
  IaC/user data grep (config form): `PasswordAuthentication yes`. Installers piped to a shell,
  location-only form (the URL may carry a token):
  `grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.terraform 'curl.*[|] *(ba)?sh' . | cut -d: -f1,2`.
- **Fix:** SSM agent and Patch Manager; key-only SSH or none; scan on push; immutable tags;
  verify installer checksums.
- **Est. $/mo:** n/a. Risk: known-CVE compromise.

## 9. Edge: CDN, WAF and origin bypass

### 9.1 The origin cannot be reached around the CDN/WAF
- **Check:** ALB or instance SGs allow `0.0.0.0/0` although CloudFront (or another CDN) sits in
  front; API Gateway default `execute-api` endpoint still on; S3 origins without OAC; a
  platform-generated origin domain still attached.
- **Evidence:** `aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing --query 'PrefixLists[].PrefixListId' --output text`
  (compare with 3.1); `aws cloudfront list-distributions --query 'DistributionList.Items[].[Id,WebACLId,DefaultCacheBehavior.ViewerProtocolPolicy]' --output text`;
  `aws cloudfront get-distribution-config --id DISTRIBUTION_ID --query 'DistributionConfig.Origins.Items[].[DomainName,OriginAccessControlId]' --output text`;
  `aws apigatewayv2 get-apis --query 'Items[].[Name,ApiEndpoint,DisableExecuteApiEndpoint]' --output text`;
  `aws apigateway get-rest-apis --query 'items[].[name,disableExecuteApiEndpoint]' --output text`.
  Probe (with consent): `curl -sI https://ORIGIN_DNS_NAME/`.
- **Why:** a reachable origin skips WAF, rate limits and DDoS protection, and makes any trust in
  CDN-only headers (viewer country, client IP) spoofable.
- **Fix:** origin SG from the CloudFront prefix list only, plus a secret origin header checked at
  the ALB; CloudFront VPC origins; `disable_execute_api_endpoint = true`; OAC on S3 origins;
  remove generated domains.
- **Est. $/mo:** n/a. Risk: WAF bypass, header spoofing.

### 9.2 WAF covers public entry points
- **Evidence:** `aws wafv2 list-web-acls --scope REGIONAL --query 'WebACLs[].[Name,ARN]' --output text`;
  `aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query 'WebACLs[].[Name,ARN]' --output text`;
  `aws wafv2 list-resources-for-web-acl --web-acl-arn ACL_ARN`
- **Fix:** managed rule groups (common, known bad inputs, IP reputation) and a rate rule.
- **Est. $/mo:** 5 per ACL + 1 per rule + 0.60 per million requests. Risk: unfiltered attacks.

### 9.3 Client IP and rate limits use trusted headers only
- **Check:** app rate limits or geo logic keyed on `X-Forwarded-For`, `X-Real-IP` or a CDN
  header without the edge overwriting it.
- **Evidence:** code grep for those headers and the framework's trusted proxy config.
  Human test: send a spoofed `X-Forwarded-For` and watch the limiter key.
- **Fix:** default to the socket peer; trust the header only from the load balancer or CDN
  ranges after a staging check proves the edge rewrites it.
- **Est. $/mo:** n/a. Risk: rate-limit bypass, abuse.

## 10. IaC change safety

### 10.1 Plans show no surprise deletes or removed Denies
- **Evidence:** the agent does not run `terraform plan`: it takes the state lock, can run
  external data sources, and drift output can print secret values. Under Commands for you to run,
  ask the human for `terraform plan -lock=false -refresh-only` (drift) and
  `terraform plan -lock=false -out=plan.out`, and warn that the output may contain secrets. The
  guard blocks `terraform show` (the JSON holds sensitive values), so also ask the human to run
  these on the saved plan and paste the addresses:
  `terraform show -json plan.out | jq -r '.resource_changes[] | select(.change.actions | index("delete")) | .address'`;
  `terraform show -json plan.out | jq -r '.resource_changes[] | select(.type | test("iam|kms|cloudtrail|log_group|security_group")) | select(.change.actions | index("no-op") | not) | .address'`.
  For those IAM addresses, compare the policy `before` and `after`, not only the `.tf` diff.
  `plan.out` stores any secrets in the plan: ask the human to delete it after the review, and
  make sure `plan.out` is git-ignored.
- **Why:** a harmless-looking PR removed a Deny on deleting log groups; agents delete
  "unused" shared resources; drift can point prod DNS at a dead IP.
- **Fix:** require plan review on IAM, KMS and logging changes; reconcile with the live API before deletes.
- **Est. $/mo:** n/a. Risk: lost guardrails, outage.

### 10.2 Agents and automation have no standing write access
- **Check:** coding agents or bots hold live cloud credentials with write rights.
- **Fix:** give agents code access only; a separate write role with a permissions boundary, an
  SCP denying `iam:*`, `kms:*`, `*:Delete*`, and a named human approval per write (`SourceIdentity`).
- **Est. $/mo:** n/a. Risk: automated destruction.

### 10.3 Debug and seed routes are off in production
- **Evidence:** grep routes and handlers for `seed`, `debug`, `bypass`, static-key guards.
- **Fix:** exist only while an env var is set; run seeders in the release step.
- **Est. $/mo:** n/a. Risk: unauthenticated admin actions.
