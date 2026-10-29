---
name: dev-prd
description: Interview the user until the PRD can be written, then write it with goals, non-goals, anti-goals and a behaviour contract in EARS. Use for "write the PRD", "spec this product", "what should we build", or when dev reaches the PRD step.
---

# Dev PRD

This skill turns an idea into `docs/prd/<product>-PRD.md`. IDs, EARS forms, the
`DECISIONS.md` format and question rules are in `../dev/references/dev-contract.md`.

## 1. Read before asking

Read `AGENTS.md`, `DECISIONS.md`, `docs/research/` and any existing PRD. Do not ask what
they already answer, and do not ask what you can decide yourself. Note what is still
unknown: goal, user, scope, limits, failure cases, success measure.

## 2. Interview in rounds

- Ask through the host's question tool, at most 5 questions per round, recommended option
  first, each question self-contained.
- Start with the biggest unknowns: who it is for, the problem, what v1 must do, what it
  must never do.
- After each round, write every answer to `DECISIONS.md` as a `D-` row (next free ID, today's
  date, `Decided`, a way to confirm). Never edit a `Decided` row; supersede it.
- Stop when you could write every section below without guessing. Do not ask for the sake
  of asking. Three rounds is plenty for most products.
- When the user cannot answer or says to skip, do not guess. Mark the gap in the PRD as
  `[NEEDS CLARIFICATION: <the exact question>]` and move on. Also add an `Open` row to
  `DECISIONS.md`.

## 3. Write the PRD

Start from `assets/PRD.md`. Fill every section.

- **Goals** are outcomes, with a measure where one exists.
- **Non-goals** are things v1 does not do, each with a one-line reason.
- **Anti-goals** are what counts as failure even if the product works.
- **Behaviour contract**: one EARS line per behaviour, IDs `B-001` upward, never reused.
  Each line must be testable on its own. Cover the unhappy paths: bad input, a failing
  dependency, a user with no access, an empty state.
- Cite the research note beside any claim that came from one.
- Keep it as short as the product allows. A small slice gets a few behaviours, not dozens.

## 4. Check it

Before handing over:

1. Every B-ID is one sentence and has a way to test it.
2. No two B-IDs say the same thing, and none contradicts a `D-` row.
3. Every `[NEEDS CLARIFICATION]` marker is also an `Open` row in `DECISIONS.md`.
4. Nothing in the PRD describes how to build it. That belongs to the tech spec.

## 5. Finish

Tell the user the file path, the count of behaviours and the count of open markers. Ask
them to review it. Do not start the next step until they approve. Then hand back to `dev`,
usually for `dev-spec`.
