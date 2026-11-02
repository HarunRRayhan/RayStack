# Codebase health checklist

Each item: **Check**, **Evidence** (Grep = code search with the agent's search tool; Run =
read-only command that passes the guard), **Why it matters**, **Fix**. Placeholders are
UPPERCASE. Replace them with literal values before running.

Run each `Run:` command once. Skip `vendor/`, `node_modules/`, `dist/`, `build/` and generated
files in every count.

## 1. Tests on core paths

- **Check**: tests exist; the core paths (money, auth, data writes) have them; tests assert
  something; none are skipped for good; no flaky signs; CI runs them.
- **Evidence**:
  - Find the tests: `tests/`, `spec/`, `__tests__/`, `*.test.*`, `*.spec.*`, `test_*.py`,
    `*_test.go`, `*Test.php`.
  - Core paths: Grep `charge`, `refund`, `invoice`, `payment`, `stripe`, `checkout`, `login`,
    `password`, `token`, `create`, `update`, `delete`, `save` in services and controllers. For
    each hit, Grep the tests for the class or function name. No hit means no test.
  - Empty tests: test bodies with no `assert`, `expect`, `should`, `assertEquals`, or only
    `assertTrue(true)`, `expect(true)`.
  - Skipped: Run `grep -rnE '[.]skip[(]|xit[(]|xdescribe[(]|@pytest[.]mark[.]skip|markTestSkipped|t[.]Skip[(]|pending' tests`
  - Flaky: Grep the tests for `sleep`, `setTimeout`, `time.sleep`, `usleep`, real hosts
    (`http://`, `https://`) with no fake or mock.
  - CI: read `.github/workflows/*.yml` or `.gitlab-ci.yml` with the file read tool and look
    for the test command.
- **Why it matters**: an untested payment or write path breaks quietly. A skipped or empty
  test reports green while checking nothing. Tests that CI does not run do not stop a bad
  merge.
- **Fix**: name the test to add, for example "`tests/Feature/RefundTest.php`: refund over the
  paid amount is rejected". Delete or fix empty tests. Replace sleeps with fake clocks and real
  calls with fakes (`Http::fake`, `nock`, `responses`, `httptest`). Add the test step to CI.

## 2. Complexity hot spots

- **Check**: files over 500 lines, functions over 50 lines, nesting deeper than 4 levels,
  functions with more than 5 parameters. A hot spot is a large file that also changes often.
- **Evidence**:
  - Churn, last 12 months: Run `git log --since='12 months ago' --format= --name-only | sort | uniq -c | sort -rn | head -20`
  - All-time churn if history is short: Run `git log --format= --name-only | sort | uniq -c | sort -rn | head -20`
  - Size of each churn hit: Run `wc -l PATH1 PATH2 PATH3`
  - Large files: Run `find . -type f -name '*.EXT' -size +20k -not -path './vendor/*' -not -path './node_modules/*'`
  - Open the top files and read the longest functions, the deepest `if`/`for` chains and the
    widest signatures.
- **Why it matters**: bugs cluster where code is both large and edited often. Every change
  there needs the whole file in your head, so it is slow and risky.
- **Fix**: name the function to extract and where it goes, for example "move tax calculation
  at `OrderService.php:212-340` into `TaxCalculator::forOrder()`". Add tests around it first.
  Replace deep nesting with early returns. Group long parameter lists into one object.

## 3. Dead code

- **Check**: unused exports and functions, routes no page or client calls, feature flags
  always on or always off, commented-out blocks.
- **Evidence**:
  - For each export or public function in the hot files, Grep its name across the repo. One
    hit (its own definition) means unused.
  - Routes: read the route files, Grep each path or name in the frontend and clients.
  - Flags: Grep `feature(`, `flag`, `isEnabled`, `FEATURE_`, `if (false`, `if (true`,
    `if False`, `if True`. Check where each flag is set.
  - Commented-out code: Run `grep -rnE '^[[:space:]]*(//|#)[[:space:]]*(if|for|return|function|def|class|const|let|var)' --include='*.EXT' .`
- **Why it matters**: dead code is read, searched and kept passing by everyone, for nothing.
  An old flag hides which branch actually runs.
- **Fix**: delete it, citing the file:line ranges. For flags, keep the live branch and remove
  the flag and its config. Git history keeps the old code.

## 4. Duplication

- **Check**: copy-pasted logic, most of all business rules (prices, tax, discounts,
  permissions, status changes) written in two places.
- **Evidence**: Grep the rule's numbers and keywords (`0.2`, `* 100`, `discount`, `vat`,
  `tax`, `status ==`, `role ==`) and compare the hits. Compare backend and frontend validation
  for the same form. Look for files with near-identical names (`helpers.js`, `utils.js`,
  `helpers2.js`).
- **Why it matters**: when a rule changes, someone updates one copy and not the other. The
  two copies then give customers different answers.
- **Fix**: name the single home for the rule, for example "`PriceCalculator::total()`", and
  list each copy to replace with a call to it. Add one test on the shared function.

## 5. Error handling

- **Check**: no swallowed exceptions, no errors logged and then ignored, one error response
  shape across the API.
- **Evidence**:
  - JavaScript, TypeScript: Run `grep -rnE 'catch [(][^)]*[)] [{][[:space:]]*[}]|catch [{][[:space:]]*[}]|[.]catch[(][(][)] => [{][}][)]' --include='*.ts' --include='*.js' .`
  - Python: Run `grep -rnE 'except[^:]*:[[:space:]]*pass|except:' --include='*.py' .`
  - Ruby: Run `grep -rnE 'rescue nil|rescue => [a-z_]+[[:space:]]*end' --include='*.rb' .`
  - PHP: Grep `catch` blocks with an empty body or only `Log::`/`error_log`.
  - Go: Grep `_ = ` on calls that return an error, and `if err != nil` blocks that only log.
  - Read each hit and the next lines: a log call with no rethrow, return or user message is
    swallowed.
  - Responses: read three error paths in the API and compare the JSON shape and status codes.
- **Why it matters**: a swallowed error on a payment or write path loses money or data with
  no alert. Mixed error shapes force every client to guess.
- **Fix**: rethrow, return an error, or handle it with a clear user message. Catch only the
  exception you expect. Send unexpected errors to the error tracker. Return one error shape
  from one handler.

## 6. Dependencies

- **Check**: a lockfile is committed; no package a major version or more behind; no package
  with no release in 2 years; no two packages doing the same job.
- **Evidence**:
  - Lockfile: Run `git ls-files -- package-lock.json yarn.lock pnpm-lock.yaml composer.lock Gemfile.lock poetry.lock uv.lock Pipfile.lock go.sum Cargo.lock`
  - Node, with consent (goes online): Run `npm outdated`
  - Last release of one package, with consent: Run `npm view PACKAGE time.modified`
  - Other stacks: read the manifest and lockfile versions; list `composer outdated --direct`,
    `bundle outdated`, `pip list --outdated` and `go list -u -m all` under "Commands for you to
    run".
  - Duplicates: Grep the manifest for pairs such as `moment` and `dayjs`, `axios` and
    `node-fetch`, `lodash` and `underscore`, `guzzle` and a second HTTP client.
- **Why it matters**: a missing lockfile means each install can get different code. Old
  majors pile up into one painful upgrade. Abandoned packages get no fixes.
- **Fix**: commit the lockfile. Upgrade one major at a time, newest first for the most used.
  Replace abandoned packages with a named maintained one. Drop the duplicate. CVEs go to
  `app-security-review`.

## 7. Config and magic values

- **Check**: no hardcoded URLs, hosts, limits or prices in logic; env vars read in one config
  module, not across the code.
- **Evidence**:
  - URLs: Run `grep -rnE 'https?://[a-z0-9.-]+' --include='*.EXT' . | grep -v test | head -50`
  - Scattered env access: Run `grep -rlE 'process[.]env|os[.]environ|getenv[(]|ENV[[]|env[(]' --include='*.EXT' .`
    Laravel: `env(` outside `config/` breaks under `config:cache`.
  - Magic numbers: read the hot files from item 2 for bare numbers in conditions and math.
- **Why it matters**: a hardcoded URL or limit needs a code change and deploy to adjust, and
  differs between environments. Env reads spread across files fail at runtime, not at boot.
- **Fix**: move each value to one config file or named constant, read env there once, and
  validate required keys at startup. Secrets in code go to `app-security-review`.

## 8. Types and lint

- **Check**: typed code is not full of escapes; a linter and formatter exist and CI runs
  them.
- **Evidence**:
  - TypeScript: Run `grep -rnE ': any|as any|@ts-ignore|@ts-expect-error|eslint-disable' --include='*.ts' --include='*.tsx' . | wc -l`
    and read `tsconfig.json` for `"strict"`.
  - Python: Grep `# type: ignore`, `Any`. PHP: `@phpstan-ignore`, `@psalm-suppress`.
  - Config: look for `eslint`, `biome`, `prettier`, `ruff`, `black`, `phpstan`, `pint`,
    `rubocop`, `golangci` config files, and the matching step in the CI files.
- **Why it matters**: `any` and ignores turn off the checks the team pays for. Without lint
  in CI, style and simple bugs are caught by reviewers, or not at all.
- **Fix**: turn on `strict` and fix the files one folder at a time. Replace each `any` with a
  real type in the hot files first. Add the lint and format check as a CI step.

## 9. Onboarding docs

- **Check**: the README says how to install, configure, run and test; an `.env.example`
  lists every env key the code reads.
- **Evidence**: read `README*` and `docs/`. Check `.env.example`, `.env.sample` or
  `.env.dist` exists (never open any other `.env*` file). Compare its keys with the env reads
  from item 7.
- **Why it matters**: a new developer loses a day guessing setup. A key missing from the
  example breaks the app on first run.
- **Fix**: add the missing README steps as exact commands. Add each missing key to
  `.env.example` with a placeholder value.

## 10. Consistency

- **Check**: one way to do each job: one HTTP client, one date library, one state library,
  one test framework, one way to query the database.
- **Evidence**: read the manifest for overlapping packages. Grep imports, for example
  `axios` and `fetch(`, `moment` and `dayjs` and `date-fns`, `redux` and `zustand`,
  `Http::` and `new Client(`, raw SQL next to the ORM for the same table. Count the files
  using each.
- **Why it matters**: two ways means two sets of bugs, two configs (timeouts, retries, auth
  headers) and a guess for every new file.
- **Fix**: pick the one used most, name it in `AGENTS.md` or the README, and list the files to
  move over. Remove the other package when the last file moves.
