---
name: aws-readonly-setup
description: Set up a read-only AWS profile (raystack-readonly) for RayStack reviews. Signs in with aws login, creates a role with ReadOnlyAccess, adds the profile and proves it can read but not write. Use when an AWS review needs live access and no read-only profile works, or for "set up read-only AWS access".
---

# AWS read-only setup

Gives the AWS reviews a profile that can only read. It creates no access keys and no users. It
makes one IAM change, a role, and asks before making it. Run it before a review, never inside
one: the review's guard blocks writes on purpose.

## 1. Check what exists

- Run `aws configure list-profiles`. If `raystack-readonly` is there, go to step 5. If the
  proof passes, you're done.
- For each profile, try `aws sts get-caller-identity --profile <p> --query Account`. Note
  which work. Name broken ones in one line each (invalid token, a region that isn't a real
  region such as `ue-east-1`). Don't fix the user's config.
- Ask once through the question tool (AskUserQuestion in Claude Code; plain text only when the
  agent has none), in one call:
  1. Which account the reviews should read. Offer the working profiles, each with the last 4
     digits of its account.
  2. Region. Offer the profile's region when it's a real one, else `us-east-1`.
  3. Consent: "Create IAM role `raystack-readonly` with the AWS-managed `ReadOnlyAccess`
     policy in account ...? This is the only write." No consent: stop and say the reviews will
     work from IaC and exports only.

## 2. Credentials for the one write

- Try the chosen profile. If its keys are invalid, or any IAM call in steps 2 and 3 gets
  `AccessDenied`, sign in through the browser instead.
- First check `raystack-setup` isn't already one of the user's own profiles. If it is, pick an
  unused name such as `raystack-setup-2`, because `aws login` overwrites the profile it writes.
  Tell the user first: "A browser tab will open. Sign in to account ... as someone who can
  create IAM roles, approve, then come back." Then run
  `aws login --profile raystack-setup --region <region>` (AWS CLI 2.32 or later). Confirm
  `aws sts get-caller-identity --profile raystack-setup` shows the chosen account. A different
  account: stop and say so. Signed in as root: stop and ask for an IAM user or SSO role
  instead. CLI too old: say which version is needed.
- Never ask for, print or write an access key.

## 3. Create the role

Pass `--profile <setup profile> --region <region>` on every command here. IAM is global, but the
CLI still errors with `NoRegion` when the profile has none.

- The trust principal is the identity from `get-caller-identity` on the profile used for the
  write. Map it like this:
  - An IAM user ARN: use it as it is.
  - `arn:aws:sts::A:assumed-role/R/S` (including SSO): use the role's real ARN from
    `aws iam get-role --role-name R --query Role.Arn`. It keeps the role's path, which SSO
    roles always have.
- `aws iam create-role --role-name raystack-readonly --max-session-duration 3600 --description "RayStack read-only reviews" --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"<principal>"},"Action":"sts:AssumeRole"}]}'`
- `aws iam attach-role-policy --role-name raystack-readonly --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess`
- `aws iam put-role-policy --role-name raystack-readonly --policy-name raystack-deny-data --policy-document file://<this skill's folder>/deny-data-policy.json`.
  ReadOnlyAccess can read data (S3 objects, SSM SecureStrings, secrets, DynamoDB rows,
  function code). This deny keeps the role to config, metrics and billing, which is all the
  reviews need. CloudWatch Logs stays readable because the bottleneck review queries it; logs
  can hold app data, so say so in the report.
- If the role already exists, check three things:
  - its attached policies are exactly `ReadOnlyAccess`;
  - its inline policies are exactly `raystack-deny-data`, matching this skill's file;
  - its trust policy names only principals in this account, with no `*` and no other account.

  Reuse it only if all three hold. Otherwise stop and report what's on it.

## 4. Add the profile

Append this section to `~/.aws/config`. Never touch `~/.aws/credentials` or any other section.
If the section already exists, leave it as it is.

```
[profile raystack-readonly]
role_arn = arn:aws:iam::<account>:role/raystack-readonly
source_profile = <the profile used in step 2>
region = <region>
```

## 5. Prove it

- `aws sts get-caller-identity --profile raystack-readonly` must show the `raystack-readonly`
  role. New roles can take a few seconds to work, so retry up to 5 times, 5 seconds apart.
- `aws iam simulate-principal-policy --profile raystack-readonly --policy-source-arn <role ARN> --action-names ec2:RunInstances s3:PutObject iam:CreateUser iam:CreateAccessKey s3:GetObject secretsmanager:GetSecretValue ssm:GetParameter kms:Decrypt dynamodb:PartiQLSelect`
  must give `implicitDeny` for the writes and `explicitDeny` for the five data reads. Any `allowed`: stop, report it, and run no review
  with this profile.
- One read: `aws ec2 describe-regions --profile raystack-readonly --query 'length(Regions)'`.

## 6. Report

Give the profile name, the last 4 digits of the account, the region, what you created, and
each proof result. The AWS reviews then use `raystack-readonly`. To undo, the user runs
`aws iam delete-role-policy --role-name raystack-readonly --policy-name raystack-deny-data`,
`aws iam detach-role-policy --role-name raystack-readonly --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess`,
then `aws iam delete-role --role-name raystack-readonly`, then deletes the profile section.

The setup profile keeps a browser-login session (about 12 hours) that `raystack-readonly`
chains through. When it expires, run `aws login --profile raystack-setup` again; the role and
profile stay.

## Never

- Create access keys or IAM users.
- Attach anything other than `ReadOnlyAccess` and the `raystack-deny-data` inline deny.
- Edit other profiles or `~/.aws/credentials`.
- Run this from inside a review.
