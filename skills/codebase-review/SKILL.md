---
name: codebase-review
description: Read-only health and maintainability review of an existing codebase in any language, with a ranked findings report. Use for "review my codebase", "code health check", "tech debt audit", "is this codebase maintainable", "what should we clean up", "missing tests", "untested payment code", "dead code", "duplicated logic", "swallowed exceptions", "outdated dependencies", "hot spot files", "onboarding docs", or a general code quality review.
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'for f in "${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh" "${CLAUDE_PLUGIN_ROOT}/../raystack/hooks/readonly-guard.sh" "$HOME/.claude/skills/raystack/hooks/readonly-guard.sh"; do [ -x "$f" ] && exec "$f"; done; echo "RayStack review is read-only: guard missing" >&2; exit 2'
---

# codebase-review

Find what makes this codebase risky or slow to change: missing tests, hot spots, dead and
duplicated code, swallowed errors, stale dependencies and missing docs. Report only. Never
patch code and never change anything live.

Siblings: layers, boundaries and import cycles go to `architecture-review`. Vulnerabilities,
CVEs and committed secrets go to `app-security-review`. Per-request cost goes to
`performance-review`. UI, accessibility and component structure go to `frontend-review`.

## 1. Read the contract

Read `../raystack/references/review-contract.md` first and follow it for inputs, live consent,
the read-only rules, questions, the report and client data. This file only adds what is
specific to codebase health.

## 2. Detect the stack

Scan the repo and note the hits. Use the per-language patterns in the checklist for the ones
found.

| Files | Stack |
| --- | --- |
| `composer.json` | PHP (Laravel, Symfony) |
| `package.json`, `tsconfig.json` | JavaScript, TypeScript |
| `requirements*.txt`, `pyproject.toml`, `Pipfile` | Python |
| `Gemfile` | Ruby |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `pom.xml`, `build.gradle*`, `*.csproj` | Java, Kotlin, .NET |
| Other | General items only, name the stack |

Also note the test folders (`tests/`, `test/`, `spec/`, `__tests__/`, `*_test.go`), the CI
files (`.github/workflows/`, `.gitlab-ci.yml`), lint and format configs, and the lockfiles.
Read `README`, `docs/`, `CLAUDE.md`/`AGENTS.md` for the core flows and known pain points.

## 3. Ask for consent

Ask once, per the contract, with one batched call to the host agent's question tool:
- whether registry lookups for outdated packages (`npm outdated`, `npm view`) may go online,
  unless the router passed it
- which flows are core (money, auth, data writes), if the repo does not say
- any folders to skip (vendored, generated, legacy being deleted)

If they decline the lookups, judge dependencies from lockfile versions only and list the
outdated commands under "Commands for you to run".

## 4. Work the checklist

Work through `references/checklist.md`, every item, with the language notes that match.

- Start from the core flows: payments, sign-in, sign-up, and any code that writes data.
  Open the route, handler, service and its tests. Trace one flow end to end. Do not grep
  and guess.
- Cite file:line for every finding. Run search commands one per Bash call.
- Skip vendored, generated and build folders (`vendor/`, `node_modules/`, `dist/`, `build/`,
  migrations, lockfiles) when counting size, duplication and dead code.
- **Hot spots.** Run the churn command in item 2 once. A file is a hot spot only when it is
  both large and in the churn top 20. Give both numbers in the finding.
- Every finding names a concrete fix: the test to add, the function to split, the file to
  delete, the package to replace. "Improve tests" is not a fix.
- Go past the checklist when the code shows a health problem it does not list.
- Hand-offs: CVEs, secrets in code and auth bugs go to `app-security-review`. Layering, god
  classes and cycles go to `architecture-review`. Slow code goes to `performance-review`.
  Component and CSS health go to `frontend-review`. Note it briefly and point there.
- Severity guide:
  - **Critical**: a core path that handles money or data writes with no tests, or a
    swallowed error on such a path.
  - **High**: hot spots (big and churning), and business rules duplicated in two places.
  - **Medium**: dead code, outdated dependencies, two ways of doing the same thing.
  - **Low**: style, lint and naming.
- Est. $/mo: write "n/a" unless the fix removes a paid service or package licence.

## 5. Write the report

Write the report per the contract with skill name `codebase-review`, at
`reviews/YYYY-MM-DD-codebase-review.md`. Under "Inputs used / missing", list the stacks
detected, the test and CI files found, whether registry lookups ran, and the folders
skipped. After the findings, add "Reviewed, found clean" (items checked with no issue). Put
outdated-package commands for other ecosystems, coverage runs and test suites under
"Commands for you to run": the review never runs them.

In chat, show the top 3 findings and the report path, then offer the PDF unless the router
runs it (contract section 5).
