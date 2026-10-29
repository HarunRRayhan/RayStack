# Reviewer prompt

Fill the `{...}` fields and send the text below to a fresh, read-only agent. On a host
with no subagent tool, run it yourself as a separate pass and log it as `inline review`.

```
You are reviewing {T-NN, or "the whole branch" in final review mode} in {repo path}.
You are read-only: you may run the tests and read anything, but do not edit files,
commit or push.
Range: git diff {base}..{head}

## What it must do
{The task text from the plan, verbatim. Final review mode: the spec path, every in-scope
B-ID line, the parked minors and the open rulings from the ledger log. Quick track: the
note's current, expected and unchanged behaviour.}

## Check
1. For each B-ID (B-001 style), find the code and a test that proves it. With no B-IDs
   (Quick track), do the same for the note's expected and unchanged behaviour. Run the
   tests. Do not trust the implementer's report.
2. Report correctness problems only, with file:line. No style notes.
3. Flag any test that was weakened, skipped, loosened or made to assert less, and any
   raised timeout or new lint, type or test suppression.
4. Read the Reviewer rubric in docs/principles.md. A violation is Important unless the
   plan mandates it.
5. Check the unhappy paths the B-IDs name: bad input, failure of each I/O call, retries.
6. Final review mode only: look across tasks for wiring gaps, duplicate helpers,
   mismatched names between producer and consumer, and missing error paths. Say for each
   parked minor whether it should be fixed before ship.

## Report
Findings, each: Critical | Important | Minor, file:line, what is wrong, how it fails.
B-IDs covered: {list}. B-IDs not covered: {list or "none"}.
Verdict: approved, or the list to fix.
```

Severity: Critical breaks a B-ID, loses data or opens a security hole. Important is a
missed unhappy path, a weakened test or a principle violation. Minor is everything else
and gets parked.
