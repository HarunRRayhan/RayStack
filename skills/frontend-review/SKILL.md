---
name: frontend-review
description: Read-only frontend code review with a ranked findings report. Use for "review my frontend", "React review", "Next.js review", "Vue or Nuxt review", "Svelte review", "Angular review", "Inertia review", "too many re-renders", "prop drilling", "fetch waterfall", "is my UI accessible", "missing alt or labels", "use client too high", "secrets in NEXT_PUBLIC", "forms double-submit", "heavy bundle", or a frontend code quality audit.
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'for f in "${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh" "${CLAUDE_PLUGIN_ROOT}/../raystack/hooks/readonly-guard.sh" "$HOME/.claude/skills/raystack/hooks/readonly-guard.sh"; do [ -x "$f" ] && exec "$f"; done; echo "RayStack review is read-only: guard missing" >&2; exit 2'
---

# frontend-review

Find what makes the frontend code hard to use, slow to render or easy to break. Report only.
Never patch code and never change anything live. For what one request costs use
`performance-review`. For deep client security use `app-security-review`. For module
boundaries and layering use `architecture-review`.

## 1. Read the contract

Read `../raystack/references/review-contract.md` first and follow it for inputs, live consent,
the read-only rules, questions, the report and client data. This file only adds what is
specific to frontend code.

## 2. Detect the stack

Read `package.json` and the config files. Note every hit. Use the stack notes in the
checklist for the ones found.

| Files | Stack |
| --- | --- |
| `next.config.*`, `app/` with `layout.*` | Next.js, app router |
| `next.config.*`, `pages/` with `_app.*` | Next.js, pages router |
| `react` in `package.json`, `vite.config.*` | React (Vite or CRA) |
| `nuxt.config.*` | Nuxt |
| `vue` in `package.json`, `*.vue` files | Vue |
| `svelte.config.*`, `@sveltejs/kit` | SvelteKit or Svelte |
| `angular.json`, `@angular/core` | Angular |
| `@inertiajs/*` with `composer.json` or `Gemfile` | Inertia (Laravel or Rails) |
| Other (Solid, Qwik, Remix, Astro islands) | General items only, name the stack |

Also note the data library (`@tanstack/react-query`, `swr`, `pinia`, `redux`, `zustand`,
`@ngrx/store`), the test runner (`vitest`, `jest`, `playwright`, `cypress`) and the
component folder. Read `README`, `docs/`, `CLAUDE.md`/`AGENTS.md` for the core user flows.

## 3. Ask the questions

Ask once, per the contract, with one batched call to the host agent's question tool:
- which flows are core (sign-up, sign-in, checkout, the main form), unless the router passed
  them or the repo says
- which pages are public and need SEO, unless the router passed it
- whether a production build output or bundle report exists to read, and where

If they skip, take sign-in, sign-up and the busiest form as core, and every page with no
auth guard as public. List these assumptions under "Inputs used / missing".

## 4. Work the checklist

Work through `references/checklist.md`, every item, with the stack notes that match.

- Start from the core flows. Open the route or page, then the components it renders, the
  data calls and the form. Trace one flow from first paint to submit. Do not grep and guess.
- Cite file:line for every finding. Run search commands one per Bash call.
- Every finding has a concrete fix: a diff, or the exact component and change.
- Count the reach. Say which routes or how many components a finding touches, for example
  "12 of 40 `<img>` tags, on 5 public pages".
- Go past the checklist when the code shows a problem it does not list.
- Hand-offs. Note it briefly and point there:
  - Request cost, query counts, server time and measured bundle bytes go to
    `performance-review`.
  - `dangerouslySetInnerHTML`, `v-html`, tokens in `localStorage` and client secrets get a
    finding here, and the deep check goes to `app-security-review`.
  - Folder layout, layering and shared module design go to `architecture-review`.
  - Full WCAG conformance needs a deeper audit with real assistive tech. Say so in the report.
- Severity guide:
  - **Critical**: users can't complete a core flow, or user data is exposed (a secret in a
    client bundle, user HTML rendered raw).
  - **High**: a core-path problem many users hit: an accessibility blocker on a core flow, a
    broken or silent error path, a big fetch waterfall on a hot page.
  - **Medium**: a local problem on one page or component.
  - **Low**: tidy-ups.
- Est. $/mo: write "n/a" unless the user gives a cost.

## 5. Write the report

Write the report per the contract with skill name `frontend-review`, at
`reviews/YYYY-MM-DD-frontend-review.md`. Under "Inputs used / missing", list the stacks
detected, the core flows and public pages used and whether they were assumed, and whether a
build output was read. After the findings, add "Reviewed, found clean" (items checked with
no issue). Put any audit or build command the user must run under "Commands for you to run".

In chat, show the top 3 findings and the report path, then offer the PDF unless the router
runs it (contract section 5).
