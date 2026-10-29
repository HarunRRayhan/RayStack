# <Slice> Implementation Plan

**Goal:** <One or two sentences: what works when this slice is done.>

**Spec:** `docs/tech-spec/<area>.md`. Read all of it, including any Complexity rows.

**Behaviours in scope:** <B-001, B-004, B-007. With no PRD, they are in the spec's `## Behaviours` section.>

## Global Constraints

- <Value or rule every task shares: names, limits, formats, conventions. Written once.>
- <Principles that bind here, from `docs/principles.md`.>

## Review Focus

1. <A risk a reviewer should hit hardest, and the task whose test covers it.>

---

### T-01: <Task name>

**Files:**
- Create: `<path>`
- Modify: `<path>` (<what changes>)
- Test: `<path>`

**Covers:** B-001, B-004

**Tests:** `<test file>`: `<test names>`

**Interfaces:**
- **Produces:** `<exact name and signature>`
- **Consumes:** <exact name from an earlier task, or "nothing">

- [ ] **Step 1: Write the failing tests:**
  - `<test name for B-001>`
  - `<test name for the unhappy path of B-004>`
- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the full suite and the project checks.**
- [ ] **Step 5: Commit** with message `<type>(<scope>): <summary>`.

### T-02: <Task name>

<Same fields as T-01.>

---

## Analyze

Run before the build. Every row must be clean.

| Check | Result | Note |
|---|---|---|
| Every in-scope B-ID maps to at least one task | | |
| Every task covers at least one B-ID | | |
| No open `[NEEDS CLARIFICATION]` or blocking `Open` D- row | | |
| No unjustified gate breach (Complexity rows present) | | |
| Produce and consume match across tasks | | |
