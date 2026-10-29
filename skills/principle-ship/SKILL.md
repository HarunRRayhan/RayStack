---
name: principle-ship
description: Apply when finishing a code change, or when asked to ship, merge, deploy or call a task done. Done means a PR opened, the diff self-reviewed, CI green, merged, and the deploy confirmed live.
---

# Ship

A change is done when it runs in production, not when the PR is open.

## Settings

Read `.raystack.json` at the repo root, else `~/.raystack.json`. No file or no key: use the defaults.

```json
{ "ship": { "autoMerge": false, "deployCheck": "Deploy workflow on main, then GET /health" } }
```

- `autoMerge` (default `false`): stop at green CI and ask through the question tool before merging. `true`: merge on green without asking.
- `deployCheck`: how to confirm the deploy (a workflow name, a URL, a health check). Unset: find it in the repo (CI workflows, README) and say which check you used.

## Steps

1. Work on a feature branch. For a user-facing change, run `local-verify` first. Open a PR.
2. Read the whole diff yourself before anyone else does, and check the docs still match the code. Fix what you find.
3. Wait for CI. Every required check must pass.
4. Merge, or ask first, per `autoMerge`.
5. Wait for the deploy to finish. Confirm it is live with a fresh request, a health check, or the deployed revision matching the merge commit.
6. Report what you confirmed and how.

## Never

- Merge with failing or pending required checks.
- Force-push a shared branch, push straight to the default branch, or skip hooks.
- Close the task on partial evidence. "Merged", "deployed" and "verified live" are three different claims. A green deploy job is not a page that loads.

## Stop and report

- CI or the deploy fails: say what failed and quote the log line.
- The change publishes, charges money, submits to a third party or drops data, and nobody approved that step. A blanket "go ahead" does not cover it.
