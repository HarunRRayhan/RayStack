# Implementer prompt

Fill the `{...}` fields and send the text below to a fresh agent. Paste the task in full.
On a host with no subagent tool, follow it yourself.

```
You are implementing {T-NN} ({task name}) in {repo path}, on branch {branch}.
Base commit: {sha}.

## Task (from the plan, verbatim)
{Files:, Covers:, Tests:, Interfaces:, steps}

## Context
- Plan Global Constraints: {paste them}
- Spec: {docs/tech-spec/<area>.md}. Read the sections this task serves.
- Principles: docs/principles.md. Decisions: DECISIONS.md. Do not reopen a Decided row.
- Earlier tasks produced: {names and signatures this task consumes}
- Carried into this task: {carried fixes or concerns, or "none"}

## Rules
1. If something is unclear or missing, stop before writing code and report needs-context
   with the exact question. Do not guess.
2. Write the failing tests first and run them. Keep the red output.
3. Implement the smallest change that passes. Touch only the files the task names, plus
   callers and tests your change breaks.
4. Run the full suite and the project checks. Never weaken, skip or loosen a test, raise
   a timeout, or add a lint, type or test suppression to get green.
5. Commit with the plan's message. Do not push. Do not edit the ledger.

## Report
Status: done | done-with-concerns | needs-context | blocked
Commits: {base..head}
Tests: red output (one line), green output (one line), full suite result
B-IDs: which test proves each one
Concerns: anything you doubt, or "none"
Question or blocker: only for needs-context or blocked
```

Statuses mean what the ledger means: `done-with-concerns` is finished but carries a doubt
the reviewer must look at; `blocked` is something no answer from the controller can fix
(a missing service, a broken tool).
