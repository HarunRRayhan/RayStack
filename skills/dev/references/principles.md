# Engineering principles

Copied into the project as `docs/principles.md`. Edit it there. Each principle is a check,
not a slogan. Reviewers treat a violation as an Important finding unless the plan mandates
it.

1. **Smallest change** that fully works. Finish every caller, test and config it touches. See the `principle-smallest-change` skill.
2. **No abstraction before a third real use.** Duplication is cheaper than the wrong abstraction. This replaces bare DRY.
3. **Ports and adapters only at real I/O boundaries:** database, network, external services. Call the framework directly inside them.
4. **One reason to change per unit.** Depend on an interface only when a second implementation or a test needs it. This replaces SOLID as a checklist.
5. **Thin edges.** Controllers, workers and tools parse input, call one use case and map the result. Rules and queries live in the use case or the repository.
6. **Explicit, loud errors.** No silent fallbacks. Validate at trust boundaries.
7. **Test behaviour against real dependencies where practical.** Write contract tests per port. Never weaken a test to make it pass.
8. **YAGNI.** No options, flags or "for later" code. Name what was skipped.
9. **Idempotent jobs and migrations,** safe to retry, with kill-and-resume tests for jobs.
10. **Small units** as a guide: functions of about 50 lines, files of about 400.
11. **A rule that matters becomes a check:** a lint, test, CI gate or hook, not prose.

## Reviewer rubric

For each principle, a violation looks like this. Cite file:line.

- Principle 1: Unrelated edits in the diff, or a changed function whose callers, tests or config were not updated.
- Principle 2: A shared helper, base class or interface with fewer than three real users.
- Principle 3: Business rules inside an adapter, or a wrapper around a framework call that is not at an I/O boundary.
- Principle 4: A unit with two reasons to change; an interface with one implementation and no test that needs it.
- Principle 5: A controller, worker or tool that queries or decides instead of calling a use case.
- Principle 6: An empty catch, a default that hides a failure, or unchecked input from outside the process.
- Principle 7: A test that mocks the thing it claims to test, was skipped or loosened, or has no contract test for its port.
- Principle 8: An unused option, flag or parameter, or code with no current caller.
- Principle 9: A job or migration that cannot be run twice safely, or a job with no kill-and-resume test.
- Principle 10: A function well over 50 lines or a file well over 400.
- Principle 11: A rule stated in prose that no lint, test, CI gate or hook enforces.
