# Dev flow contract

One source for the formats that every `dev-*` skill uses. Link it, do not copy it.

## Decisions

`DECISIONS.md` at the repo root is a table:

```
| ID | Date | Decision | Status | Supersedes | How to confirm |
| --- | --- | --- | --- | --- | --- |
| D-004 | 2026-10-29 | Use Postgres for all state | Decided | none | `grep -r sqlite src/` returns nothing |
```

- Status is `Decided`, `Open`, `Deferred` or `Superseded by D-NNN`.
- A `Decided` row is never edited. To change it, add a new row that names the old ID in
  `Supersedes`, then set the old row to `Superseded by D-NNN`.
- Every row has a way to confirm it: a command, a test or a file to look at.
- A settled decision is never asked again. Read `DECISIONS.md` before asking the user anything.
- Write a separate ADR file only when options were really weighed. Link it from the row.

## IDs and EARS

- `B-NNN` is a behaviour, `D-NNN` a decision, `T-NN` a task.
- IDs are never reused, even when the thing they name is dropped.
- Write each behaviour as one EARS line, testable on its own:

```
B-001: WHEN a signed-in user submits an empty title, THE SYSTEM SHALL reject it with a field error and save nothing.
```

- Other forms: `THE SYSTEM SHALL ...` (always true), `WHILE <state>, ...`, `IF <fault>, THEN ...`.
- Tasks and tests cite the B-IDs they cover. A behaviour with no task is a gap.

## Ledger

The plan `docs/plans/YYYY-MM-DD-<slice>.md` has a ledger beside it,
`docs/plans/YYYY-MM-DD-<slice>-ledger.md`. The top is a strict status table. Only status
updates touch it.

```
| Task | Status | Commit | Notes |
| --- | --- | --- | --- |
| T-01 | done | a1b2c3d | |
| T-02 | in-progress | | |
| T-03 | todo | | |
```

Statuses: `todo`, `in-progress`, `done`, `done-with-concerns`, `needs-context`, `blocked`.

Below the table is an append-only running log. It holds fix rounds with commit ranges,
rulings with their cost if wrong, parked minors and final-review notes:

```
### 2026-10-29 T-02 review round 1
Reviewer: B-003 not covered (no test for the empty case). Fixed in b4c5d6e..e7f8a9b.
Ruling: keep the retry at 3, cost if wrong: one extra slow request.
Parked minor: rename `tmp` in `parse.ts`.
```

## Subagents

- Each task gets an implementer and a reviewer.
- Reviewers are read-only. They check by behaviour ID, report correctness only, and flag
  weakened tests, raised timeouts and added suppressions.
- Set the model tier on purpose: a cheap one for mechanical tasks, the strongest for the
  final review.
- Group small tasks into one dispatch to keep the agent count down.
- **Hosts with no subagent tool:** implement the task, then review it in a separate pass
  against the checklist below. Record `inline review` in the ledger log.

Reviewer prompt checklist:

1. Read the task and its B-IDs. Check each B-ID against the diff and the tests.
2. Report correctness problems only, with file:line. No style notes.
3. Flag any test that was weakened, skipped or loosened to pass.
4. Flag any raised timeout or new lint, type or test suppression.
5. Check `docs/principles.md`. A violation is Important unless the plan mandates it.
6. Say which B-IDs are covered and which are not. End with: approved, or the list to fix.

## Questions

Ask through the host's question tool (AskUserQuestion in Claude Code). Ask at most 5 per
round, put the recommended option first, and make each question self-contained. Plain text
only when the host has no question tool. Each answer becomes a `D-` row in `DECISIONS.md`.

## Session start

A new session reads `AGENTS.md`, then the ledger, then runs the project's smoke check if
one exists, then continues from the first ledger row that is not `done`. This is how a long
build survives a context reset.
