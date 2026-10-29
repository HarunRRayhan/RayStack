# AGENTS.md: <PRODUCT>

This file holds every decision, spec, plan and research note for <PRODUCT>. Agents working on <PRODUCT> start here.

<!-- hub-only -->
This folder is a knowledge hub. It holds no application code. Agents working on any <PRODUCT> repository start here.
<!-- /hub-only -->

## Read in this order
1. `DECISIONS.md`: every product, stack and execution decision, dated. Settled decisions are not re-asked.
2. `docs/prd/`: what the product does and does not do, as B-ID behaviours.
3. `docs/architecture/`: the parts, the data flow and the security boundaries.
4. `docs/tech-spec/`: per-area specs.
5. `docs/principles.md`: binding on all code.
6. `docs/plans/`: implementation plans, each with its ledger.
7. `docs/research/`: working material, dated, with a source beside every fact.

<!-- hub-only -->
## Repositories
| Repo | Local path | Role |
| --- | --- | --- |
| <PRODUCT> hub | `<HUB PATH>` | this folder; planning only |
| <REPO NAME> | `<REPO PATH>` | <ROLE> |

Each code repo's `AGENTS.md` points back here and holds only how to run that repo. Knowledge lives here; code lives there. A decision made while coding is recorded in `DECISIONS.md` here, not in the code repo.
<!-- /hub-only -->

## Rules that bind every repo
- Engineering principles: `docs/principles.md`. Reviewers treat a violation as Important.
- <BINDING RULE: one line each, with the check that enforces it>

## Workflow
- New feature or change: research if needed, write or update the PRD and spec, write a plan in `docs/plans/`, then build task by task with a fresh implementer and reviewer per task.
- Research goes in `docs/research/` as dated markdown.
- Decisions are asked one at a time; settled ones are logged in `DECISIONS.md`.
<!-- hub-only -->
- One plan and one ledger live in the hub. Each code repo gets its own branch, its own reviews and its own PR.
<!-- /hub-only -->

## Environment facts
- <TOOLCHAIN, PORTS, HOSTING: what an agent needs to run things>
- Secrets live in git-ignored files. Never echo a value into chat, logs or commits.
