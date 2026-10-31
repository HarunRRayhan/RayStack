---
name: app-security-review
description: Read-only application security review of the code with a ranked findings report. Use for "security audit of my app", "is my app secure", "find IDOR bugs", "check authorization", "mass assignment", "SQL injection or XSS", "open redirect or SSRF", "are my secrets committed", "dependency CVEs", or a Laravel, Node/Express/Next.js, Django or Rails security review.
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'for f in "${CLAUDE_PLUGIN_ROOT}/skills/raystack/hooks/readonly-guard.sh" "${CLAUDE_PLUGIN_ROOT}/../raystack/hooks/readonly-guard.sh" "$HOME/.claude/skills/raystack/hooks/readonly-guard.sh"; do [ -x "$f" ] && exec "$f"; done; echo "RayStack review is read-only: guard missing" >&2; exit 2'
---

# app-security-review

Find real, exploitable security bugs in the application code: authorization, injection,
redirects, auth flows, secrets, sessions, uploads and dependencies. Report only. Never patch
code, and never change anything live.

This review reads code only. It never sends requests to a running app: no `curl`, no browser,
no probing of staging or production. Each finding instead gives the exploit request for the
user to try on their own environment.

## 1. Read the contract

Read `../raystack/references/review-contract.md` first and follow it for inputs, live consent,
the read-only rules, questions, the report and client data. This file only adds what is
specific to application security.

## 2. Detect the stack

Scan the repo and map each hit to a framework note in the checklist. Review every checklist
area, using the notes for the stacks that match.

| Files | Framework note |
| --- | --- |
| `artisan`, `composer.json` with `laravel/framework`, `routes/web.php`, `app/Http/` | Laravel |
| `package.json` with `express`, `fastify`, `koa` or `next`; `app/` or `pages/` routes, `middleware.ts` | Node/Express/Next.js |
| `manage.py`, `settings.py`, `urls.py`, `requirements*.txt` or `pyproject.toml` with `django` | Django |
| `Gemfile` with `rails`, `config/routes.rb`, `app/controllers/` | Rails |
| Other web frameworks (Flask, FastAPI, Spring, Go, .NET) | General areas only, note the framework |

| Lockfile | Audit command |
| --- | --- |
| `package-lock.json`, `npm-shrinkwrap.json` | `npm audit --omit=dev` |
| `composer.lock` | `composer audit --no-plugins --no-scripts` |
| `requirements*.txt` (pinned) | `pip-audit -r requirements.txt --disable-pip --no-deps` (or `--require-hashes` when hashed) |
| `Gemfile.lock` | `bundle-audit check` |
| `yarn.lock`, `pnpm-lock.yaml`, `poetry.lock`, `uv.lock`, `go.sum`, `Cargo.lock` | `osv-scanner scan --no-call-analysis=go -r --format json .` |

Also read `README`, `docs/`, `SECURITY.md` and any `CLAUDE.md`/`AGENTS.md` for the roles, the
trust model (who is anonymous, who is a user, who is an admin) and known incidents.

## 3. Ask for consent

Dependency audits and osv-scanner send the lockfile's package list to public advisory
registries, and semgrep fetches its rules from the registry, so they are live calls. Ask once, per the contract, with one batched call to the host agent's question
tool:
- whether the dependency audits listed above, osv-scanner and semgrep may run, unless the router passed it
- which roles exist and which data must never cross between users, if the repo does not say

If they decline, list the audit commands under "Commands for you to run". Run the audits only
in the exact forms above, never `audit fix`, `bundle audit` or another verb. If there is
no lockfile for an ecosystem, or the tool is not installed ("command not found"), skip that
audit and say so in "Inputs used / missing". Never fail the review over it. Areas 13 and 14 of the
checklist have the secret and code scan steps; the forms are in `../raystack/references/scanners.md`.

## 4. Work the checklist

Work through `references/checklist.md`, every area, with the framework notes that match.

- Open the route, controller, model and template for each candidate and trace the request to
  the response. Do not grep and guess.
- Cite file:line for every finding. Run search commands one per Bash call; grep for monitored
  tool names with a bracket class, per the contract.
- **Finding bar.** A finding needs a concrete exploit: the request an attacker sends, as which
  user (anonymous, another signed-in user, or the owner), and what they gain. Without one, it
  goes under a "Worth hardening" section after the findings, never ranked as a finding.
  Framework defaults (CSRF tokens, template escaping, ORM binding) are not findings unless the
  code shows them disabled or bypassed.
- Dependency CVEs: confirm the app's own code reaches the vulnerable function before ranking
  it. Otherwise it goes under "Worth hardening" with the upgrade.
- Logging findings (area 12) use a **Blind spot** line (the attack that would go unseen)
  instead of **Exploit**, and rank at most Medium.
- Go past the checklist when the code shows a risk it does not list.
- Cloud and deploy exposure belong to the sibling skills. Note it briefly and point to
  `aws-security-review` or `infra-review`.
- Severity guide:
  - **Critical**: anonymous account takeover, remote code execution, SQL injection, secrets in
    tracked files, or any user reading or changing every other user's data.
  - **High**: IDOR between users, stored XSS, privilege escalation by mass assignment, SSRF
    to internal addresses, auth bypass on one route.
  - **Medium**: reflected XSS, open redirect, missing rate limit on login or reset, CSRF on a
    state-changing route, a reachable dependency CVE.
  - **Low**: weak cookie flags, verbose errors, issues that need an admin account to exploit.
- Est. $/mo: write "n/a" unless the user gives a cost of the incident.

## 5. Write the report

Write the report per the contract with skill name `app-security-review`, at
`reviews/YYYY-MM-DD-app-security-review.md`. Under "Inputs used / missing", list the stacks
detected, the audits run or skipped and why. In each finding, add an **Exploit** line (request,
user, gain) after **Evidence**. After the findings, add "Worth hardening" (unranked) and
"Reviewed, found clean" (the areas checked with no issue). Put the skipped audits and any
exploit for the user to confirm under "Commands for you to run".

In chat, show the top 3 findings and the report path, then offer the PDF unless the router runs it (contract section 5).
