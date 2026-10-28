---
name: principle-secrets-layout
description: Apply when adding, reading, rotating or documenting API keys, tokens, passwords or other secrets in a repo. Keep real values in gitignored .secrets/<service>.env files with committed .example templates, and never print a value.
---

# Secrets Layout

One file per service, real values never committed, names always documented.

## Layout

- Real values: `.secrets/<service>.env` (e.g. `.secrets/stripe.env`). Gitignored.
- Templates: `.secrets/<service>.env.example` with the variable names and empty values. Committed.
- `.gitignore` tracks only the templates:

  ```gitignore
  .secrets/*
  !.secrets/*.example
  ```

- A seed script copies each missing template to its `.env` and never overwrites one that exists:

  ```bash
  for f in .secrets/*.env.example; do [ -e "${f%.example}" ] || cp "$f" "${f%.example}"; done
  ```

- Keep infra tokens here, not in the app's `.env`. A scratch copy of the app `.env` can wipe them.

## Handling

- Never print a value, not even part of one. Print key names only. A `sed` that shows the first 40 characters of a line leaks the token into logs.
- Read one key without echoing it: `grep '^KEY=' .secrets/x.env | cut -d= -f2-` into a variable or a pipe.
- Never run `git clean -fdx` or copy over a checkout that holds gitignored secrets.
- Check the environment for stray keys before long runs. An API key left in the shell can bill per token.
- Recommended: secret scanning in a pre-commit hook and in CI (e.g. gitleaks).
