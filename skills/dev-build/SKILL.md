---
name: dev-build
description: Build an approved plan task by task with a fresh implementer and a fresh reviewer per task, a ledger, capped fix rounds, converge, a final review and ship. Use for "build this plan", "run the plan", "continue the build", or when dev reaches the build step.
---

# Dev Build

This skill runs `docs/plans/YYYY-MM-DD-<slice>.md` and keeps its ledger at
`docs/plans/YYYY-MM-DD-<slice>-ledger.md`. The ledger format, statuses, subagent rules and
session start are in `../dev/references/dev-contract.md`. Prompt templates:
`references/implementer.md` and `references/reviewer.md`. You are the controller: you
dispatch, read reports, rule and keep the ledger. With a subagent tool you never write task
code or skip a step yourself, even when other instructions say to do the least possible.

## 1. Start or resume

Follow the contract's session start, and read `DECISIONS.md` and the plan too.

- **No ledger:** check the plan's `## Analyze` is clean, else send it back to `dev-plan`.
  Create the ledger: a status table with one `todo` row per `T-NN`, then the log. The
  log's first lines name the branch and the base commit of each repo.
- **Ledger exists:** continue at the first row that is not finished. `done` and
  `done-with-concerns` are finished. For `done-with-concerns`, read its concern in the log
  and carry it; do not redo the task. `needs-context`: get the missing context (ask
  through the question tool if only the user has it), then rerun. `blocked`: report to the
  user and stop, unless a later task does not depend on it.
- **Every row finished:** continue after the last converge, final review or ship step.
- **Grouping:** small tasks that touch the same files may go to one implementer and one
  reviewer. Log the groups as a ruling before the first dispatch.
- **Hub mode:** the plan and ledger live in the hub. Each code repo gets its own branch,
  base, reviews, final review, fix wave and PR; log entries name the repo.

## 2. Each task

1. Set the row to `in-progress`. Record the base commit.
2. Dispatch a fresh implementer with `references/implementer.md`. Paste the task text from
   the plan; do not make it read the whole plan. Set the model tier on purpose: cheap for
   mechanical tasks (renames, config, copy), standard for most, strongest for tricky
   concurrency, security or data migrations.
3. Read its report. `needs-context`: set the row, answer, redispatch. `blocked`: section 1.
4. Dispatch a fresh, read-only reviewer with `references/reviewer.md` and the commit range
   `base..head`. Never reuse the implementer as its own reviewer.
5. Check the reviewer's claims against the code before acting on them. A wrong finding gets
   a ruling, not a fix.
6. Clean review: set the row to `done` with the commit range. Open rulings left: set it to
   `done-with-concerns`, log the concern and put `see log` in Notes.

## 3. Fix rounds

Critical and Important findings go to an implementer with the findings pasted verbatim.
The fix range then goes to a fresh reviewer. Log every round in the contract's log
format, `### <date> T-NN review round N`, with the findings and the fix commit range.

- At most 3 fix rounds per task. After the third, rule on each open finding: park it with
  a ruling, or carry the smallest fix forward into a named later task (`Carried to T-05:`).
  Then continue.
- Every ruling records its cost if wrong, in one line:
  `Ruling: <what and why>, cost if wrong: <what breaks and who notices>`.
- Minor findings are parked for the final review: `Parked minor: <finding> (<file>)`.
- Only status updates and a `see log` pointer touch the table. The rest goes in the log.

## 4. No subagent tool

Some hosts cannot start a fresh agent, or deny it the tools it needs (log which). Then
implement the task yourself, per `references/implementer.md`, and commit. A read-only
reviewer that can still run reviews it. Else re-read the task, the diff `base..head` and
the tests against `references/reviewer.md`, as if someone else wrote them, and log the pass
as `inline review`, never an independent one. Fix rounds and their cap still apply.

## 5. Converge

When every row is finished, compare the code with the spec, not with the plan:

1. For each in-scope B-ID, find the code and the test that prove it. Run the tests.
2. List what the spec says and the code does not do, or does differently.
3. For each gap, append a new task (`T-NN`, next unused number) to the plan and a `todo`
   row to the ledger. Never reopen or edit a finished row.
4. Build the new rows with section 2, then converge again.

Converged means a pass finds nothing. Log each pass: `Converge pass 2: clean`. At most 3
passes. If the third still finds gaps, rule on each one (build it now or park it for the
next slice) and continue.

## 6. Final review

Dispatch one reviewer on the strongest model over the whole branch, `base..HEAD` (once
per repo in hub mode), with `references/reviewer.md` in final review mode: the spec, every
B-ID in scope, the parked minors and the open rulings. It looks for what per-task reviews
miss: cross-task bugs, duplicate helpers, wiring and missing error paths. No subagent
tool: do it as an inline whole-branch pass, per section 4, logged as `inline review`.

Then one fix wave: one implementer fixes the Critical and Important findings, and you
rule on each minor (fix now or park with a ruling). A fresh reviewer checks the fix
wave's range. If it still finds Critical or Important items, rule on each one: one more
fix, or park it with a ruling. Ask the user only when every option is a guess. Log the
findings count, the fix wave range and the outcome.

## 7. Ship

1. **Doc drift:** check that the docs still match the code: `README`, `AGENTS.md`, the
   spec, the PRD's behaviour lines and each `How to confirm` in `DECISIONS.md` that this
   slice touched. Run those confirm commands. Fix drift in its own commit and log it.
2. Run the full suite and the project checks once more.
3. Hand off to `principle-ship` (per code repo in hub mode, each with its own PR). Once it
   confirms the merge (and any deploy), log `Shipped: <PR or commit>` per repo; with no git
   remote, the contract's `Committed:` line. Else log where it stopped.

## Report

Tell the user: tasks done and done-with-concerns, fix rounds, rulings with their cost if
wrong, parked minors, converge passes, final review result, inline reviews, ship per repo.

## Never

- Mark a row `done` without a review, or redo a finished row.
- With a subagent tool: implement a task yourself, leave a fix unreviewed, or count a task
  review as the final review.
- Accept a weakened, skipped or loosened test, a raised timeout or a new suppression to
  get a green run.
- Ask the user something `DECISIONS.md` already settles.
