---
name: dev-gaps
description: Find which dev-flow documents an existing project is missing (research, PRD, architecture, tech specs, plan, decisions) and fill them, drafted from the code where it can and asked where it cannot. Use for "/raystack project update", "/raystack project gaps", "what docs is this project missing", "document this existing codebase", "add a PRD to this repo".
---

# Dev gaps

This skill brings an existing project up to the RayStack dev flow. It reads the code, lists
what is missing, then fills each gap with the matching `dev-*` skill. It writes documents
only, never code. Formats and question rules are in `../dev/references/dev-contract.md`.

## 1. Inventory

Read `AGENTS.md`, `DECISIONS.md` and `docs/` if they exist, then the code: the README, the
manifests (`package.json`, `composer.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`...),
the entry points, routes, models or schema, jobs, tests, CI and deploy files. Never open
`.env*` files (`.env.example` is fine), `*.tfstate*` or credential files.

Fill this table and show it to the user:

| Artifact | Where | Status |
| --- | --- | --- |
| Hub files | `AGENTS.md`, `DECISIONS.md` | present / missing |
| Research | `docs/research/` | present / missing / stale (older than the stack in use) |
| PRD | `docs/prd/` | present / missing / partial (behaviours with no B-ID) |
| Architecture | `docs/architecture/system-overview.md` | present / missing / drifted |
| Tech specs | `docs/tech-spec/` | per area: present / missing / drifted |
| Principles | `docs/principles.md` | present / missing |
| Plan and ledger | `docs/plans/` | none / open (unfinished ledger) / shipped |

Drifted means the document names a part, route, table or service the code no longer has, or
the code has a major part the document does not name. Give one example per drift with
file:line.

## 2. Ask what to fill

Ask once through the question tool: fill every gap (recommended), pick which, or stop at the
table. Then fill in this order, skipping what is present:

1. **Hub:** `dev-hub` single-repo steps. Never replace an existing `AGENTS.md`; append.
2. **PRD from behaviour:** draft B-IDs from the routes, screens, jobs and tests that exist.
   Each line cites the file it came from. Then ask, one question per call, only what code
   cannot tell: who it is for, goals, non-goals, anti-goals. `dev-prd` checks the result.
3. **Architecture as built:** `dev-spec` writes `system-overview.md` from the code, with the
   `## Stack` table read from the manifests and logged as `D-` rows ("as found in code", with
   the file as the way to confirm). Do not re-decide the stack.
4. **Tech specs as built:** one area spec per area with real design, each with `Serves:`
   the B-IDs from step 2 and `Status: as-built. Date: YYYY-MM-DD.`
5. **Research:** only if the user wants it; `dev-research` on the market or on the stack.

A drifted document is updated, never rewritten: change the lines that are wrong, add a dated
`D-` row for each real change and keep the rest.

## 3. Finish

Report the table again with the new status, the files written, the B-ID count, open
`[NEEDS CLARIFICATION]` markers and the `D-` rows added. Ask the user to review. Then offer
the next step: `dev` Standard for the next slice, `dev-review` to check the plan and the
architecture against the code, `dev-migrate` to move part of the stack, or `dev-refactor` to clean up the code.
