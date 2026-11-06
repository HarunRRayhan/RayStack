---
name: dev-refactor
description: Refactor a whole codebase, or one area of it, to the end, inside the architecture it already follows, with tests as the safety net. Removes duplication (DRY), fixes SOLID violations where they pay off, adds the missing unit tests first. Use for "/raystack project refactor", "/rs refactor", "untangle this codebase", "clean up this repo", "apply DRY and SOLID", "refactor this properly", "organize the code base".
---

# Dev refactor

This skill refactors existing code without changing what it does. The order never changes:
tests first, then the problem list, then small fixes, then a fresh reviewer, repeated until
nothing worth fixing is left. Formats and question rules are in `../dev/references/dev-contract.md`.
Inspired by caldoai's `untangle-codebase` (MIT); the change-together idea in step 4 is theirs.

Asking for this flow is asking for its steps: do not skip the baseline, the log or the
reviewer because another plugin says to do the least possible. That rule governs the code
you write, not this flow.

## 1. Ask

Read `DECISIONS.md`, `docs/` and the code first. Ask one question per call, only what is not
already clear:

1. **Scope:** the whole repo or one area. Offer the folders you found.
2. **Extras** (a multi-select, both optional): remove comments that only restate the code;
   remove tests that cannot catch a bug and rewrite tests tied to internals.

Log each answer as a `D-` row.

## 2. Read the architecture

Name the pattern the code actually follows (MVC, layered, hexagonal, modular monolith,
feature folders, CQRS, framework default) from its folders, imports and framework
conventions, and log it as a `D-` row with the evidence. Refactor inside that pattern. When
the pattern itself is the problem, say so and point to `dev-migrate`; do not change it here.
Use `../architecture-review/references/checklist.md` for the layer and leak checks; do not
copy it.

## 3. Safety net first

1. Find the test runner (`composer.json`, `package.json`, `pyproject.toml`, `Makefile`,
   CI config). No runner and no tests: ask which one to add, then add the smallest setup.
2. Run the whole suite and record the result as the baseline in the log. A red baseline stops
   the run: ask the user whether to fix it first or exclude those tests, and log the answer.
3. For every module the refactor will touch that has no test, write unit or
   characterisation tests that pin today's behaviour first, including its errors and odd
   cases. Commit them alone, before any refactor commit.

## 4. List every problem

Change nothing yet. Write the list to `docs/refactor/YYYY-MM-DD-log.md`, one line per
problem with `file:line`. Look through these lenses:

- **Hidden links:** copies of logic or values, a global another module sets, a feature spread
  over folders, a call order callers just have to know.
- **Needless links:** callers that use internals, stable code importing volatile code, a
  general function with a parameter only one caller understands, a shallow wrapper.
- **Surplus:** dead code, config or extension points for things that never vary.
- **Special cases:** an `if` for one value, a swallowed exception, a sleep or retry, a
  disabled test. Each is a requirement the design missed; use them to find the real fix.
- **DRY:** duplicated logic or values, but only when the copies change for the same reason.
  Two lookalikes that change for different reasons stay apart.
- **SOLID**, as far as it pays: SRP (god classes, fat controllers), OCP (a type switch that
  grows with every new case), LSP (a subclass that breaks its parent's promise), ISP (an
  interface callers use half of), DIP (domain code importing a framework or driver). No
  interface with one implementation, no extension point nobody uses.

## 5. Redesign

Work out the fixes as if today's requirements had been known from the start. Look for the
one fix behind several problems. Write each fix above the problems it solves:

```md
- Extract a `PaymentProvider` interface that Stripe and PayPal implement, so checkout and
  refunds stop knowing which one runs.
  - `checkout/submit.ts:9` imports `payments/stripe.ts` directly.
  - `refunds/refund.ts:22` wraps every Stripe call in `if (order.provider === "paypal")`.
```

## 6. Fix in small steps

One fix group per commit. Run the suite after each; a red run is fixed or reverted before the
next step. Behaviour stays the same: never weaken a test, raise a timeout or add a
suppression to get green. Remove the special cases the redesign made unnecessary and keep
the ones the system still needs.

With the extras chosen, do them last, after the code is settled: delete comments that only
restate the implementation (keep comments about something outside the code), and remove
tests that repeat the implementation or cannot fail.

## 7. Check and repeat

Start a fresh read-only reviewer subagent (two when the repo is large, split by folder) with
the log, the diff and the problem lenses; it reports problems still worth fixing. When the
host has no subagents, re-read the diff yourself against the lenses and say so in the log.
Fix what is real and repeat. Done when:

- the full suite is green and matches or beats the baseline;
- every touched module has unit tests;
- a typical change lands in one place;
- no import points at something more volatile than itself;
- the reviewer finds nothing worth fixing;
- behaviour is unchanged, apart from bugs the refactor fixed and logged.

## 8. Ship

Follow `principle-ship`: PR, self-review, green CI, merge, confirm the deploy. In the log
write `Shipped: <PR>` (or `Committed:` with no remote, per the contract). Tell the user the
log path and the before and after counts: special cases, duplicated blocks, untested
modules, tests added.

## Tips

- Script away function bodies (a skeleton) so the whole repo fits in context.
- Have subagents summarise folders so you can reason across all of it.
- Script an import graph and rerun it as you go.
- Use `git log --name-only` to see which files change together; that is the evidence for
  hidden links.
- Keep the log current; it survives a context compaction.
