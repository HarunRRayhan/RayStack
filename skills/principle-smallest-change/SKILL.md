---
name: principle-smallest-change
description: Apply when writing, fixing or refactoring code, adding a dependency, or choosing between designs. Make the smallest change that fully solves the task and finish every place it must reach.
---

# Smallest Change

Solve the whole problem with the least new code.

## Before you write

- List every place the change must reach: callers, tests, fixtures, config, exports, docs.
- Check the basics. Grep that the function or class exists with that exact name. Read the installed docs or `--help` instead of guessing flags, APIs or model names.

## Pick the first option that works

1. Skip it if nobody needs it. No speculative options, flags, abstractions or "for later" code.
2. Reuse what the codebase already has, the way the surrounding code uses it.
3. Use the standard library or an installed dependency. Never add a dependency for a few lines.
4. Otherwise write the minimum that works.

## Finish it

- Lazy about the solution, never about the change. Update every caller, test and config it breaks.
- Every behavior change gets a test. A regression test must fail before the fix.
- Comment only the why the code cannot show.
- A known limit gets a comment: `shortcut: <limit>, <when to upgrade>`.
- Don't touch values you don't understand. A timeout cut from 300 s to 30 s looks tidy and breaks slow calls.
- Keep migrations additive. Destructive cleanup (dropping a column, deleting an old path) goes in a later PR.

## Never cut

Validation at trust boundaries, error handling that prevents data loss, security, accessibility.
