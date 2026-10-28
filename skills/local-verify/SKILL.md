---
name: local-verify
description: Use when a change needs a real local browser check before release. Starts the app on throwaway data, checks the changed route in a browser, cleans up and reports what was and was not verified.
---

# Local verify

Confirm a user-facing change works in a real browser on your machine before you ship it. This is
a playbook, not a review: no report file. It starts servers and may run migrations, so it has
no read-only guard. The rules below are the guard.

## 1. Detect how the app starts

- Look in `package.json` scripts (`dev`, `start`), then `php artisan serve`,
  `manage.py runserver`, `rails s`, a Procfile, or `docker compose`.
- More than one plausible way: ask through the host's question tool. Don't guess.
- Pick a free port. Bind to 127.0.0.1.

## 2. Isolate the data

- Use a throwaway database: copy the SQLite fixture to a temp file, or make a temp DB and run
  the migrations against it.
- Set overrides on the server process only (`DB_DATABASE=/tmp/x.db cmd`). Never `export` them
  in the shell: they leak into every later command.
- Never edit, replace, back up or write `.env`. It may be a symlink to another checkout.
- Frameworks can rank real environment variables above the test config, so a leftover
  `DB_*`, `APP_ENV`, `APP_KEY` or mail variable can win. Check what the process really sees.
  Clear any cached config (`bootstrap/cache/config.php` and similar) before starting.
- Never point at production or a shared database. No live payments, no real email: use the log
  or array mailer and test keys.
- Login needed: create a throwaway user in the temp database. Never use real credentials.
- Read secrets into process env only, and never print them.

## 3. Build assets

- Build the way the repo's own instructions say, if it has any.
- Confirm the page loads the local build. A stale dev-server or hot file left behind (such as
  `public/hot`) can send the browser to a dead host and break hydration.

## 4. Check the changed route

- Use whatever browser automation you have (a Playwright or Chrome tool, or the host's own).
- Check the interaction or content the change affects, a mobile width if layout is involved,
  and the console for errors.
- Prefer DOM state and computed styles over screenshots.
- If you have no browser tool, say so and stop here. Don't claim the page was verified.

## 5. Clean up

- When done, stop only the server you started. Delete only your temp database and disposable artifacts.
- Leave `.env` and any other worktree untouched.

## 6. Report

State the route, the viewports, what passed, and what you did not check.

## Caveats

- Caches can serve stale content. After changing content or config, use a fresh cache or clear
  the cache you are actually reading before trusting the result.
- A local build proves nothing about a deploy. Check the pipeline and the live response
  separately.
