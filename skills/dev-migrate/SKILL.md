---
name: dev-migrate
description: Plan and run a move of part or all of a project to another language, framework, database or platform, step by step with behaviour kept the same and proven by tests. Use for "/raystack project migrate", "migrate this service to Rust", "move from Express to Go", "port this to TypeScript", "switch from MySQL to Postgres", "rewrite this part in another stack".
---

# Dev migrate

This skill turns "move X to Y" into research, a migration spec and a plan that `dev-build`
runs. The rule throughout: the old code keeps working until the new code is proven to do the
same thing. Formats and question rules are in `../dev/references/dev-contract.md`.

## 1. Ask what to move

Read `DECISIONS.md`, `docs/` and the code first. Then ask, one question per call, only what
is not already clear:

1. **What part?** Offer the modules, services or layers you found, plus "the whole project".
2. **To what?** The target language, framework, database or platform.
3. **Why?** Speed, cost, hiring, safety, a dead dependency. The reason decides what to
   measure at the end.
4. **Limits:** downtime allowed, deadline, data that must not be lost or reshaped.

Log each answer as a `D-` row.

## 2. Map what exists

For the chosen part, list in `docs/tech-spec/migration-<part>.md` under `## Current`:
its entry points (routes, CLI, jobs, events), the data it reads and writes, its callers, its
external calls, its config and secrets by name only, and the tests that cover it. Code with
no test is marked: it needs a characterisation test before it moves.

## 3. Research the target

Run `dev-research` on the target: maturity, libraries for each thing the part does today,
how it is deployed, how it talks to the code that stays. One table row per gap ("no mature
library for X"). A gap with no answer is an `Open` row and may stop the migration; say so.

## 4. Write the migration spec

In the same file, add:

- `Serves:` at the top, listing the B-IDs below, so `dev-plan` finds the spec.
- `## Behaviours`: B-IDs (the next free numbers after the PRD's) saying the new part does
  what the old one does (same inputs, same outputs, same errors, same data), plus one per stated reason ("p95 under 50 ms").
- `## Approach`: strangler by default. The new part runs beside the old, behind a route,
  flag or queue switch; traffic moves in steps; the old part is deleted last. A big-bang
  cutover needs a `## Complexity` row.
- `## Data`: dual-write or one-time copy, how it is checked (row counts, checksums), and the
  rollback for each step.
- `## Parity tests`: the same test cases run against old and new; the switch moves only
  when both pass.
- `## Done when`: every caller uses the new part, the old code and its config are deleted,
  and the reason is measured.

Log the stack change as a `D-` row that supersedes the `## Stack` row it replaces, and
update that row in `docs/architecture/system-overview.md`.

## 5. Plan and build

Hand to `dev-plan`: one task per step (characterisation tests, new part skeleton, parity
for each entry point, switch, data move, delete old), each step shippable and reversible on
its own. After the user approves the plan, `dev-build` runs it.

Tell the user the spec path, the B-IDs, the steps, the open rows and any gap that blocks.
