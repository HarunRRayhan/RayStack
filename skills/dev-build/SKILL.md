---
name: dev-build
description: Build an approved plan task by task with a fresh implementer and a fresh reviewer per task, a ledger, capped fix rounds, converge, a final review and ship. Use for "build this plan", "run the plan", "continue the build", or when dev reaches the build step.
---

# Dev Build

This skill runs `docs/plans/YYYY-MM-DD-<slice>.md` and keeps its ledger at
`docs/plans/YYYY-MM-DD-<slice>-ledger.md`. The ledger format, statuses, subagent rules and
session start are in `../dev/references/dev-contract.md`. Prompt templates:
`references/implementer.md` and `references/reviewer.md`. You are the controller: you
dispatch, read reports, rule and keep the ledger. You do not skip a review.

## 1. Start or resume

Follow the contract's session start: read `AGENTS.md`, `DECISIONS.md`, the plan, then the
ledger, and run the smoke check if the project has one.

- **No ledger:** check the plan's `## Analyze` is clean, else send it back to `dev-plan`.
  Create the ledger: a status table with one `todo` row per `T-NN`, then the log. The
  log's first lines name the branch and the base commit.
- **Ledger exists:** continue at the first row that is not finished. `done` and
  `done-with-concerns` are finished. For `done-with-concerns`, read its concern in the log
  and carry it; do not redo the task. `needs-context`: get the missing context (ask
  through the question tool if only the user has it), then rerun. `blocked`: report to the
  user and stop, unless a later task does not depend on it.
- **Grouping:** small tasks that touch the same files may go to one implementer and one
  reviewer. Log the groups as a ruling before the first dispatch.
- **Hub mode:** the plan and ledger live in the hub. Each code repo gets its own branch or
  worktree, its own reviews and its own PR. Note the repo on each task's log entries.

## 2. Each task

1. Set the row to `in-progress`. Record the base commit.
2. Dispatch a fresh implementer with `references/implementer.md`. Paste the task text from
   the plan; do not make it read the whole plan. Set the model tier on purpose: cheap for
   mechanical tasks (renames, config, copy), standard for most, strongest for tricky
   concurrency, security or data migrations.
3. Read its report. `needs-context` or `blocked`: set the row, answer or rule, redispatch.
4. Dispatch a fresh, read-only reviewer with `references/reviewer.md` and the commit range
   `base..head`. Never reuse the implementer as its own reviewer.
5. Check the reviewer's claims against the code before acting on them. A wrong finding gets
   a ruling, not a fix.
6. Clean review: set the row to `done` with the commit range. Open rulings left: set it to
   `done-with-concerns` and put the concern in Notes.

## 3. Fix rounds

Critical and Important findings go to an implementer with the findings pasted verbatim.
The fix range then goes to a fresh reviewer. Log every round:

```
### 2026-10-29 T-02 fix round 1/3
Reviewer: B-003 not covered (no empty-title test). Fixed in b4c5d6e..e7f8a9b.
```

- At most 3 fix rounds per task. After the third, rule on each open finding: park it with
  a ruling, or carry the smallest fix forward into a named later task (`Carried to T-05:`).
  Then continue.
- Every ruling records its cost if wrong, in one line:
  `Ruling: <what> - <why> - cost if wrong: <what breaks and who notices>`.
- Minor findings are parked, not fixed now: `Parked minor: <finding> (<file>)`. The final
  review sees them.
- Only status updates touch the table. Everything else is appended to the log.

## 4. No subagent tool

Some hosts cannot start a fresh agent. Then implement the task yourself, following
`references/implementer.md`, and commit. Then do a separate review pass: re-read the
task, the diff `base..head` and the tests against `references/reviewer.md`, as if someone
else wrote them. Log the pass as `inline review`. Never call it an independent review,
here or in the final report. Fix rounds and their cap still apply.

## 5. Converge

When every row is finished, compare the code with the spec, not with the plan:

1. For each in-scope B-ID, find the code and the test that prove it. Run the tests.
2. List what the spec says and the code does not do, or does differently.
3. For each gap, append a new task (`T-NN`, next unused number) to the plan and a `todo`
   row to the ledger. Never reopen or edit a finished row.
4. Build the new rows with section 2, then converge again.

Converged means a pass finds nothing. Log each pass: `Converge pass 2: clean`.

## 6. Final review

Dispatch one reviewer on the strongest model over the whole branch, `base..HEAD`, with
`references/reviewer.md` in final review mode: the spec, every B-ID in scope, the parked
minors and the open rulings. It looks for what per-task reviews miss: cross-task bugs,
duplicate helpers, wiring and missing error paths.

Then one fix wave: one implementer fixes the Critical and Important findings, and you
rule on each minor (fix now or park with a ruling). A fresh reviewer checks the fix
wave's range. Log the findings count, the fix wave range and the outcome.

## 7. Ship

1. **Doc drift:** check that the docs still match the code: `README`, `AGENTS.md`, the
   spec, the PRD's behaviour lines and each `How to confirm` in `DECISIONS.md` that this
   slice touched. Run those confirm commands. Fix drift in its own commit and log it.
2. Run the full suite and the project checks once more.
3. Hand off to `principle-ship`. In hub mode, run it once per code repo, each with its own
   PR, and record each PR in the hub ledger.

## Report

Tell the user: tasks done and done-with-concerns, fix rounds used, rulings with their cost
if wrong, parked minors, converge passes, the final review result, which reviews were
inline, and the ship status per repo.

## Never

- Mark a row `done` without a review, or redo a finished row.
- Accept a weakened, skipped or loosened test, a raised timeout or a new suppression to
  get a green run.
- Ask the user something `DECISIONS.md` already settles.
