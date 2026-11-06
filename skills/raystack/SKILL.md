---
name: raystack
description: Entry point for everything in RayStack. Use for "/raystack", "what can RayStack do", development work ("new project", "project new", "project update", "project gaps", "project review", "project migrate", "project refactor", "refactor this", "start a project", "write a PRD", "plan this", "build this", "fix this bug properly") and read-only reviews ("review my AWS", "review my database", "audit my stack", "which review should I run", cloud cost, security, bottlenecks, deploys, scaling, databases, app code security, performance, N+1 queries, CI/CD security or GitHub Actions security, architecture, CQRS, MVC, frontend, reliability, availability, code quality or tech debt), and scans that run several reviews as one job ("scan", "scan all", "scan security"), and updating RayStack ("update raystack").
---

# RayStack

RayStack is Harun R. Rayhan's skill pack for building and reviewing software. This is its front
door (`/rs` is the same entry point with a shorter name): it works out what the user wants and runs the right skills.

| Job | Skill |
| --- | --- |
| Build: idea, PRD, spec, plan, reviewed build, ship | `dev` (it picks Quick, Standard or Full) |
| Review or scan: read-only reviews, one or many, with ranked reports | `audit` (it picks the reviews and runs them) |
| Check a change in a real browser | `local-verify` |

Four principle skills load on their own; this router never runs them: `principle-ship`,
`principle-smallest-change`, `principle-ask-with-question-tool`, `principle-secrets-layout`.

## 0. Pick the job (in this order; the first match wins)

- The request starts with "scan" (`/raystack scan all`), or uses a scan phrase ("security scan", "performance scan", "scan and fix", "full audit", "check everything"): hand off to `audit` with the words. "scan" elsewhere in a request ("build a barcode scan screen") is not this rule.
- `project new|update|gaps|review|migrate|refactor`, `new project`, or "review the plan" or "review the spec": `dev`, project commands (`dev-review` for the last two).
- `/raystack update`, "update raystack", "which version": follow [references/update.md](references/update.md).
- Any other request that starts with "review" or "audit" (`/raystack review architecture`): hand off to `audit` with the words.
- Words about making or changing something ("start", "PRD", "plan", "build", "fix", "where are we"): hand off to `dev` and stop here, even when told to do the least possible (see `dev`).
- Other words about auditing, cost, security, speed, scaling, the database, architecture, CQRS, MVC, frontend, reliability, availability or code quality: `audit`.
- Bare `/raystack`: ask once through the question tool, "Build something" (runs `dev`) or
  "Review this repo" (runs `audit`). Recommend "Build" when `docs/plans/` or `DECISIONS.md` exists.
- An unfinished ledger in `docs/plans/`, and words not clearly a review or scan: `dev`, as above.

## Hand off

Claude Code: invoke the Skill tool with the user's words in the args, by the name your agent
lists (`raystack:audit` or `raystack:dev` in a plugin install, else the bare name). Other
agents: read `../audit/SKILL.md` or `../dev/SKILL.md` and follow it.
