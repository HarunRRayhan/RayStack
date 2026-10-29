---
name: dev-plan
description: Write an implementation plan for one vertical slice, with tasks that name their files, behaviour IDs and tests, then analyze it until clean. Use for "plan this", "break it into tasks", or when dev reaches the plan step.
---

# Dev Plan

This skill writes `docs/plans/YYYY-MM-DD-<slice>.md`. IDs, EARS forms, the ledger and
question rules are in `../dev/references/dev-contract.md`. The build step creates the
ledger; this skill does not.

## 1. Pick the slice

One plan per vertical slice: a thin cut that runs from the edge to the data and can be
shown working on its own. Not one plan per layer. If the work is bigger, plan the first
slice and say what the next ones are.

Read `AGENTS.md`, `DECISIONS.md`, `docs/principles.md`, the PRD and the tech specs that
list the slice's B-IDs under `Serves:`. A Standard slice may have no PRD. Then write the
B-IDs it needs at the top of the plan, as EARS lines, and number them as the contract says.

## 2. Write the plan

Start from `assets/plan.md`. Fill the header: Goal, Spec, Global Constraints (the values
every task shares, written once, so tasks do not restate them), and a short Review Focus
of the risks a reviewer should hit hardest.

Then tasks, `T-01` upward, in build order. Each task:

- is small enough for one implementer to finish and one reviewer to read;
- names its `Files:` (create and modify), `Covers:` (one or more B-IDs), and `Tests:`;
- lists what it produces and what it consumes, as exact names and signatures;
- starts with failing tests, then runs them to see red, then the implementation, then the
  full suite, then a commit with a message in the plan.

Cover the unhappy paths the B-IDs name. Tests assert behaviour, not internals.

## 3. Analyze

End the plan with `## Analyze` and run it. The plan is not ready until every line is clean.

1. Every in-scope B-ID maps to at least one task.
2. Every task covers at least one B-ID. A task with none is cut or the B-ID is missing.
3. No open `[NEEDS CLARIFICATION]` in the plan, the specs or the PRD, and no `Open` row
   in `DECISIONS.md` that the slice depends on.
4. No unjustified gate breach: compare each spec and task against the simplicity and
   anti-abstraction gates in `docs/principles.md`. A breach without a `## Complexity` row
   in the spec fails.
5. Produce and consume match: every name, signature, path or file one task consumes is
   produced by an earlier task, spelled the same.

Fix the plan and run it again. Record the result in the `## Analyze` section as a table
of check, result, note. If something cannot be fixed without the user, ask through the
question tool (at most 5 per round) and record the answer as a `D-` row.

## 4. Finish

Tell the user the plan path, the task count, the B-ID coverage and the analyze result.
Ask them to review. Do not start the build until they approve. Then hand back to `dev`,
usually for `dev-build`.
