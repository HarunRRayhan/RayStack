---
name: dev
description: Entry point for the RayStack development flow. Use for "/dev", "start a new project", "plan this feature", "build this", "fix this bug properly", "where are we", or any request to take work from idea to shipped code.
---

# Dev

This skill runs the RayStack development flow. It reads the project state, picks the
smallest track that fits and hands off. The shared formats (decisions, IDs, ledger,
subagents, questions) are in `references/dev-contract.md`. The default engineering
principles are in `references/principles.md`.

| Skill | Does |
| --- | --- |
| `dev-hub` | Sets up the project folder, `AGENTS.md` and `DECISIONS.md` |
| `dev-research` | Researches the problem and the options |
| `dev-prd` | Writes the PRD with B-ID behaviours |
| `dev-spec` | Writes the tech spec and architecture |
| `dev-plan` | Turns the spec into a task plan |
| `dev-build` | Creates the ledger and builds the plan task by task |

## 1. Detect state

Look for these, in this order, and say what you found:

- a hub: `AGENTS.md` and `DECISIONS.md` at the root. If `AGENTS.md` is a pointer to a hub
  path, read `DECISIONS.md`, `docs/` and the plans and ledgers from that hub path instead;
- research in `docs/research/`, a PRD in `docs/prd/`, a spec in `docs/tech-spec/` and
  `docs/architecture/`;
- a plan in `docs/plans/` and its ledger.

Resume `dev-build` on the newest ledger in `docs/plans/` whose log has no `Shipped:` line
(the contract's session start). Never restart the plan. Read `DECISIONS.md` first so
settled questions are not asked again. If it is missing, see section 2: Standard runs
`dev-hub`'s single-repo steps first, Full starts with `dev-hub`, and Quick adds only
`DECISIONS.md`, from `../dev-hub/assets/DECISIONS.md`, when a decision needs logging.

## 2. Pick the track

Pick the smallest track that fits. Say which one and why.

- **Quick** (a bug or a small change): no PRD, no hub. Do these inline:
  1. Write the expected and must-stay-unchanged behaviour down: in the reply for a fix of a
     few lines, else in `docs/plans/YYYY-MM-DD-<fix>.md` with the current behaviour too.
  2. Make the change with a test.
  3. Always review it, even for one line: a fresh reviewer checks the diff against the
     expected and unchanged behaviour. With no subagent tool, use the contract's inline
     review. Never skip this step; say which kind of review ran.
  4. Ship with `principle-ship`. With no git remote, say so and stop at the commit.
- **Standard** (one slice of work): run `dev-spec` if no spec serves the slice (with no
  PRD it writes the slice's B-IDs), then `dev-plan`, then `dev-build`.
- **Full** (a new product): run `dev-hub`, `dev-research`, `dev-prd`, `dev-spec`,
  `dev-plan`, `dev-build`, in that order.

If the work grows past its track, say so and move it up one track. Do not carry on
quietly.

## 3. Replan

When the plan no longer fits, replan:

1. Update the affected spec lines and the plan tasks they touch.
2. Log a dated `D-` row in `DECISIONS.md` that supersedes the old one.
3. Leave ledger rows that are already `done` or `done-with-concerns` as they are. Add or
   change only rows that are not finished.
4. Re-run the plan's `## Analyze` until clean, then resume `dev-build`.

## 4. After launch

Once the code is live, point to the `raystack` skill for cost, security, scaling, database
and infrastructure reviews.
