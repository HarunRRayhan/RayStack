# Scanners

The guard allows six scanners, only in the forms below. Write each one as shown: one bare
command, no redirect, only the contract's pipe filters. Anything else is denied.

`<skills>` is the literal path `realpath` prints for `<this review's base directory>/..`.
Run `realpath` once and paste that path into the command: `$(...)` is denied.

Install: `brew install gitleaks semgrep osv-scanner zizmor actionlint hadolint`. Never run it
for the user. There is no allowed `which`, `command -v` or `gitleaks version`: run the form
below, and "command not found" means the tool is missing.

## Forms

Each line in a `scanner` block is checked against the guard by `tests/test-guard.sh`.

```scanner
gitleaks dir . --redact --no-banner -f json -r - -c <skills>/raystack/references/gitleaks.toml
gitleaks git . --redact --no-banner -f json -r - -c <skills>/raystack/references/gitleaks.toml
semgrep scan --config p/default --metrics off --disable-version-check --json . | jq '[.results[] | {check_id, path, line: .start.line}]'
osv-scanner scan --no-call-analysis=go -r --format json .
zizmor --offline .
actionlint -shellcheck= -pyflakes=
hadolint Dockerfile
```

- gitleaks: `--redact` and that exact `-c` are required. Report rule, file and line only.
- semgrep: always `--json` piped to `jq` that keeps only `check_id`, `path` and `start.line`.
  Its plain text prints the matched line, which can be a secret. It goes online for rules.
- osv-scanner: sends package lists to osv.dev. Add `--no-resolve` or a path if needed.
- zizmor and hadolint take paths (`.` or a file). Both are local.
- semgrep and osv-scanner need live consent (contract section 2); the rest are local.
- `.gitleaksignore`, `gitleaks:allow` comments and `osv-scanner.toml` can hide findings. Find
  them with `grep -rl '[g]itleaks:allow' .` (names only; `-n` would print the secret).
- Confirm each hit by reading the code.
