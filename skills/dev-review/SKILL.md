---
name: dev-review
description: Read-only mid-build review of a project's architecture, tech specs and plan against the code, with a ranked findings report. Use for "/raystack project review", "review the architecture against the docs", "review the plan", "does the code match the spec", "is the plan still right".
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'for f in "${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh" "${CLAUDE_PLUGIN_ROOT}/../raystack/hooks/readonly-guard.sh" "$HOME/.claude/skills/raystack/hooks/readonly-guard.sh"; do [ -x "$f" ] && exec "$f"; done; echo "RayStack review is read-only: guard missing" >&2; exit 2'
---

# Dev review

Check the design documents against each other and against the code, in the middle of a
build. Report only: never edit code, specs, plans or ledgers. Formats are in
`../dev/references/dev-contract.md`; the report follows
`../raystack/references/report-template.md` with skill `project-review`: `Est. $/mo` is
`n/a`, and each fix is a document or task edit, not a code diff.

## 1. Read

`DECISIONS.md`, the PRD's behaviour contract, `docs/architecture/`, `docs/tech-spec/`,
`docs/principles.md`, the newest plan and its ledger, then the code those documents name.
If there is no architecture, spec or plan, write a short report that lists what is missing,
offer `dev-gaps` and stop there.

## 2. Check

**Architecture**
1. Every part, store and service in the overview exists in the code, and every major part
   in the code is in the overview (drift, with file:line).
2. The code follows the `## Stack` rows and `D-` decisions (a second database, a new
   framework or a service split with no `D-` row is a finding).
3. The Simplicity and Anti-abstraction gates (`dev-spec` section 5, `docs/principles.md`):
   layers, wrappers, services or queues with one user and no `## Complexity` row.
4. Coupling: modules reaching into each other's tables or internals; a cycle between modules.
5. I/O boundaries: database, network and third-party calls sit where the spec says, with the
   failure path the spec names (timeout, retry, error shown).

**Specs and PRD**
6. Every B-ID is served by a spec (`Serves:`) and covered by a plan task or a test.
7. No spec or task contradicts a `Decided` row; open `[NEEDS CLARIFICATION]` markers that
   block work still in `todo`.

**Plan and ledger**
8. Tasks still `todo` fit the code as it is now (they name files and functions that exist).
9. The ledger matches git: `done` rows have their commit; no task stuck `in-progress` with
   no commit for over a week; `done-with-concerns` items were followed up.
10. Order and size: a task that depends on a later task; a task too big to review in one go.

For data access depth (N+1 queries, indexes) point to `performance-review` and
`database-review` rather than repeating them.

## 3. Rank and report

Severity: **Critical** the design or plan will ship wrong behaviour (a B-ID broken or
unserved on a path in use); **High** drift or a broken decision that the next tasks build
on; **Medium** over-design, coupling, a stale task; **Low** wording and tidy-ups. Each
finding has file:line evidence and a fix that names the document or task to change.

Write `reviews/YYYY-MM-DD-project-review.md`. Tell the user the path, the counts per
severity and the top three. To act on it, offer `dev` (replan, section 3) so fixes go
through the plan and the ledger.
