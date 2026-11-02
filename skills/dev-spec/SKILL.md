---
name: dev-spec
description: Write the architecture and per-area tech specs from the PRD (or, on Standard, the slice's own Behaviours), and copy the default principles into the project. Use for "write the tech spec", "design the architecture", "how should we build it", or when dev reaches the spec step.
---

# Dev Spec

This skill turns an approved PRD, or on Standard the slice's own `## Behaviours`, into
`docs/architecture/` and `docs/tech-spec/<area>.md`. IDs, EARS forms, the `DECISIONS.md`
format and question rules are in `../dev/references/dev-contract.md`.

**Standard track with no PRD:** write the slice's behaviours as EARS lines, numbered as
the contract says, in a `## Behaviours` section at the top of the slice's area spec. That
section stands in for the PRD's behaviour contract for `dev-plan` and its analyze.

## 1. Read before writing

Read `AGENTS.md`, `DECISIONS.md`, the PRD (its `## Behaviour contract`) if there is one,
`docs/research/` and the code that already exists. Do not ask what these answer.

## 2. Put the principles in place

If `docs/principles.md` is missing, copy `../dev/references/principles.md` to it. It is
editable there. Every spec is written against it, and the reviewer rubric at its end is
what the build checks the code against.

## 3. Choose the structure

**Stack (Full track only):** settle each row below that is not already `Decided` in
`DECISIONS.md`, from the PRD's limits and the research's technical options. On Standard,
read the stack from the code and `DECISIONS.md`, and never decide it again.

| Decide | Default unless the PRD or research says otherwise |
| --- | --- |
| Language and framework | what the team already ships; else the most mature fit |
| Shape | one deployable (modular monolith); services only with a Complexity row |
| Data store | one relational database; add another only for a named B-ID |
| Hosting and deploy | a managed platform; Kubernetes only with a Complexity row |
| Auth, jobs, cache | the framework's built-ins first |
| Repo layout | one repo |

Ask the user about a row only when the choice is real (question rules below). Record each
row as a `D-` row with the options and the reason; write an ADR only for a close call.

Then write `docs/architecture/system-overview.md`, starting with a `## Stack` table
(choice, why, `D-` ID), then the parts, how they talk, where data lives, where the I/O
boundaries are. A Complexity row for the stack goes in the overview's `## Complexity`
section. Then write one `docs/tech-spec/<area>.md` per area that has real design in it
(data model, API, jobs, auth, delivery). Skip areas with nothing to say.
Add `docs/tech-spec/README.md` as an index: file, then what it covers.

Ask when a choice is real and the answer changes the design. Use the host's question tool,
at most 5 per round, recommended option first. Record each answer as a `D-` row. Write a
separate ADR only when options were weighed.

## 4. Write each area spec

Start from the shape below. Keep it as short as the area allows.

```
# <Area>

Serves: B-001, B-004, B-007
Status: draft. Date: YYYY-MM-DD.

## Behaviours   Standard with no PRD only: one EARS line per B-ID

## Design        how it works, with the data, the interfaces and the failure paths
## Boundaries    which I/O it touches and the port for each
## Test approach how each served B-ID is proven
## Complexity    only when a gate is breached, see below
```

- `Serves:` lists every B-ID the area implements. Every B-ID in scope must appear in at
  least one spec. A spec with no B-ID is either dead weight or a missing behaviour: ask.
- Design for the unhappy paths the B-IDs name: bad input, failing dependency, no access.
- Say what was skipped on purpose (YAGNI) in one line.
- Mark an unanswered design question `[NEEDS CLARIFICATION: <question>]` and add an
  `Open` row to `DECISIONS.md`. Do not guess.

## 5. Gates

Check each spec against `docs/principles.md` before handing over.

- **Simplicity:** the smallest design that serves the B-IDs, no extra layer, option or service.
- **Anti-abstraction:** no abstraction before a third real use, no port inside the app core.

A breach is allowed only with a row in the spec's `## Complexity` section:
`Breach | Why it is needed | Simpler option rejected because`. No row, no breach. If a
gate is not breached, leave the section out.

## 6. Finish

Tell the user the file paths, the stack `D-` IDs, the B-IDs served per file, any B-ID
not yet served, the count of open markers and the count of Complexity rows. Ask them to review. Do not start
the next step until they approve. Then hand back to `dev`, usually for `dev-plan`.
