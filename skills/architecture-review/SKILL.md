---
name: architecture-review
description: Read-only code-level architecture review of an existing codebase with a ranked findings report, no design docs needed. Use for "review my architecture", "is this MVC done right", "fat controllers", "layer leaks", "is our CQRS correct", "hexagonal or DDD review", "are we over-engineering", "import cycles", "god classes", "modular monolith review", "distributed monolith", "shared database between services", or a Laravel, Rails, Django, Express/NestJS, Spring, .NET, Go or Next.js architecture review.
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'for f in "${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh" "${CLAUDE_PLUGIN_ROOT}/../raystack/hooks/readonly-guard.sh" "$HOME/.claude/skills/raystack/hooks/readonly-guard.sh"; do [ -x "$f" ] && exec "$f"; done; echo "RayStack review is read-only: guard missing" >&2; exit 2'
---

# architecture-review

Find which architecture the code uses, then check the code follows it. Report only. Never
patch code and never change anything live. No design docs are needed: the code is the source.

Siblings: when design docs exist, use `dev-review` (it checks docs against code). N+1 and
per-request cost go to `performance-review`. Schema goes to `database-review`. Load goes to
`scaling-review`. General code health goes to `codebase-review`.

## 1. Read the contract

Read `../raystack/references/review-contract.md` first and follow it for inputs, live consent,
the read-only rules, questions, the report and client data. This file only adds what is
specific to architecture.

## 2. Detect the stack and the pattern

Scan the repo and note the hits. Use the stack hints in the checklist for the ones found.

| Files | Stack |
| --- | --- |
| `artisan`, `composer.json` with `laravel/framework` | Laravel |
| `Gemfile` with `rails`, `app/models/` | Rails |
| `manage.py`, `settings.py`, `django` in requirements | Django |
| `package.json` with `express` or `@nestjs/core` | Express, NestJS |
| `pom.xml` or `build.gradle` with `spring-boot` | Spring |
| `*.csproj`, `*.sln` | .NET |
| `go.mod` | Go |
| `next.config.*`, `app/` or `pages/` with `next` in `package.json` | Next.js |
| Other | General items only, name the stack |

Then name the pattern or patterns in use, each with file:line evidence (checklist item 1):
MVC, layered (controller, service, repository), CQRS, hexagonal (ports and adapters), DDD,
modular monolith, microservices, serverless. A repo can mix them, for example layered inside
each module of a modular monolith. Say which part uses which. If no pattern is clear, say so,
and judge the code against the pattern its own folder names claim.

Also read `README`, `docs/`, `CLAUDE.md`/`AGENTS.md` for stated rules, such as "controllers
never touch the ORM". Stated rules count as the chosen pattern.

## 3. Ask for inputs

Ask once, per the contract, with one batched call to the host agent's question tool:
- which areas are core paths (the ones new features copy), if the repo does not say
- whether the repo is one service among several, and where the others live,
  unless the router passed it
- any known pain, such as "every change touches five files" or "the read side lags"

This review needs no live access. If they do not answer, use the code only and list each
assumption under "Inputs used / missing".

## 4. Work the checklist

Work through `references/checklist.md`, every item that fits the detected patterns. Skip the
items for patterns the code does not use, and list them as "not applicable".

- Start from two or three core flows, for example signup, the main create action and the main
  list page. Trace each one from route to storage and back. Do not grep and guess.
- Cite file:line for every finding. Run search commands one per Bash call.
- Judge the code against the pattern it chose, not a pattern you prefer. A plain MVC app with
  thin controllers is fine. Suggesting CQRS or hexagonal for a small CRUD app is itself
  over-engineering.
- Count repeats. One leak is local. The same leak in eight controllers is the house style, and
  the next feature will copy it. Say how many places, and list up to five.
- Every fix is concrete: name the class or function to create or move, and show a short diff
  or the target file layout. "Refactor this" is not a fix.
- Go past the checklist when the code shows a structural problem it does not list.
- Hand-offs: query cost goes to `performance-review`, schema and index design to
  `database-review`, behaviour at 10x load to `scaling-review`, docs drift to `dev-review`,
  lint, tests and dead code to `codebase-review`. Note it briefly and point there.
- Severity guide:
  - **Critical**: a pattern violation already causing wrong behaviour or a data corruption
    risk, such as two services writing one table or a query handler that writes.
  - **High**: a violation on a core path that the next features will copy.
  - **Medium**: local violations and over-abstraction.
  - **Low**: naming and tidy-ups.
- Est. $/mo: write "n/a". Architecture costs show up as time, not a bill.

## 5. Write the report

Write the report per the contract with skill name `architecture-review`, at
`reviews/YYYY-MM-DD-architecture-review.md`. Under "Inputs used / missing", list the stacks
detected and any assumptions. Before "Findings", add a "Patterns detected" section: each
pattern, the part of the code that uses it and its file:line evidence. In each finding, add a
**Pattern** line (which pattern the rule comes from) after **Evidence**. After the findings,
add "Reviewed, found clean" (items checked with no issue) and "Not applicable" (items skipped
because the pattern is not used).

In chat, show the top 3 findings and the report path, then offer the PDF unless the router
runs it (contract section 5).
