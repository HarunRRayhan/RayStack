# Architecture checklist

Each item: **Check**, **Evidence** (Grep = code search with the agent's search tool; Run =
read-only command that passes the guard), **Why it matters**, **Fix**.
Placeholders are UPPERCASE. Replace them with literal values before running.

Work item 1 first. Then work only the items for the patterns it found, plus the module and
cross-cutting items, which apply to every codebase. List skipped items as "not applicable".

## 1. Detect the pattern

- **Check**: which pattern or patterns the code uses, and where. Name each with evidence.
- **Evidence**: read the folder tree two levels deep, then open one core flow end to end.
  - MVC: controllers, models and views or templates, with no service layer between them.
  - Layered: `Services/`, `services/`, `Repositories/`, `repository/`, `*Service`,
    `*Repository` classes, called in order controller to service to repository.
  - CQRS: `Commands/` and `Queries/` folders, `*CommandHandler`, `*QueryHandler`, a bus
    (`CommandBus`, `QueryBus`, `Mediator`, `MediatR`, `@nestjs/cqrs`), `ReadModel`,
    `Projection`, `Projector`, separate read and write models or tables.
  - Hexagonal: `Domain/`, `Application/`, `Infrastructure/`, `ports/`, `adapters/`, interfaces
    in the core with implementations outside it.
  - DDD: `Aggregate`, `AggregateRoot`, `ValueObject`, `DomainEvent`, `*Repository` per
    aggregate, bounded-context folders.
  - Modular monolith: `Modules/`, `modules/`, `packages/`, `apps/` or `src/<context>/` in one
    deploy, each with its own controllers, services and models.
  - Microservices: several services with their own build files and deploy configs, clients
    calling each other over HTTP, gRPC or a broker.
  - Serverless: one function per handler, `serverless.yml`, SAM or CDK function definitions,
    `functions/`, Vercel or Netlify functions.
- Stack hints:
  - Laravel: `app/Http/Controllers`, `app/Models`, `resources/views`; `app/Services`,
    `app/Actions`, `app/Repositories` for layered; `app/Domain` or `src/` for DDD;
    `Modules/` (nwidart) for modular. Facades and `DB::` show where the ORM is reached.
  - Rails: `app/controllers`, `app/models`, `app/views`; `app/services`, `app/interactors`,
    `app/commands` for layered; `packs/` or `components/` (packwerk, engines) for modular;
    `package.yml` dependency lists.
  - Django: apps are the modules; `views.py`, `models.py`, templates; `services.py` or
    `selectors.py` for layered; cross-app imports of `models` show coupling.
  - Express/NestJS: Express `routes/`, `controllers/`, `services/`; NestJS `@Module`,
    `@Controller`, `@Injectable`, `imports: [...]` for module edges, `@nestjs/cqrs` for CQRS.
  - Spring: `@Controller`/`@RestController`, `@Service`, `@Repository`, `JpaRepository`;
    package per layer or per feature; Axon for CQRS; ArchUnit tests state the rules.
  - .NET: `Controllers/`, `Services/`, `Infrastructure/`, `Domain/` projects in the `.sln`;
    project references show layer edges; MediatR for CQRS.
  - Go: `cmd/`, `internal/`, `pkg/`; packages per feature or per layer; interfaces declared by
    the consumer; `handler`, `service`, `store` or `repo` packages.
  - Next.js: `app/` route handlers and server components, server actions (`'use server'`),
    `lib/` or `server/` for services; database calls inside components show the layers.
- **Why it matters**: every later item judges the code against the pattern it chose. A wrong
  guess here makes every finding wrong.
- **Fix**: none. Record the result under "Patterns detected".

## 2. MVC: fat controllers

- **Check**: controller actions that hold business rules, long branches, calculations,
  several model writes or outside calls.
- **Evidence**: open the controllers on core paths. Flag actions over about 30 lines, or
  controllers over about 300 lines. Grep for transactions, price or status maths, and mail or
  HTTP calls inside controller folders.
- **Why it matters**: the rule can only be reused by copying it. The same rule in a console
  command, job or API route drifts from the web version.
- **Fix**: move the rule to one action, service or model method, for example
  `PlaceOrder::handle($cart, $user)`, and leave the controller to validate, call it and return.

## 3. MVC: business logic in views or templates

- **Check**: templates or components that query, compute prices, check permissions by hand
  or decide workflow state.
- **Evidence**: Grep templates for ORM calls (`::where`, `.objects.`, `.where(`, `find`),
  `@php` blocks, `{% if user.role ==`, inline maths on money. In React or Next.js, components
  that fetch and then apply rules before rendering.
- **Why it matters**: the rule is invisible to tests and to the API, so the API and the page
  give different answers.
- **Fix**: compute it in the controller, a view model, a presenter or a policy, and pass the
  result. Permissions go through the framework's policy or guard.

## 4. MVC: models doing HTTP or mail

- **Check**: models or ORM hooks that send mail, call outside APIs or read the request.
- **Evidence**: Grep model files for `Mail::`, `send_mail`, `deliver_`, `Http::`, `fetch(`,
  `axios`, `requests.`, `request()`, `Auth::`, `current_user`; model events and callbacks
  (`booted`, `after_save`, `post_save`, `@AfterInsert`) that do any of these.
- **Why it matters**: saving a row now has side effects. Seeders, imports and tests send real
  mail or calls, and a failed call can roll back or half-finish a save.
- **Fix**: raise an event or call a service after the save, and send from a listener or job.

## 5. Layered: layer leaks

- **Check**: a layer skipping the one below it, or reaching up. Examples: a controller calling
  the ORM directly when a service layer exists; a repository returning an HTTP response,
  redirect or view; a service reading the request or session.
- **Evidence**: Grep controller folders for ORM calls (`Model::query`, `DB::`, `.objects.`,
  `prisma.`, `getRepository`, `EntityManager`, `_context.`) and count them against controllers
  that go through services. Grep repositories and services for `response(`, `redirect(`,
  `HttpResponse`, `res.json`, `ResponseEntity`, `request()`, `req.`.
- **Why it matters**: the layer's rules (validation, caching, events, tenancy scopes) are
  skipped on the leaking path, so the same data is handled two ways.
- **Fix**: route the call through the existing service, add the missing service method if
  needed, and return plain data from repositories. Where the stack allows, add a rule that
  fails the build (ArchUnit, deptrac, packwerk, eslint `no-restricted-imports`).

## 6. CQRS: command handlers that return read data or query

- **Check**: command handlers that return entities, DTOs for display or lists, or run read
  queries to build a response.
- **Evidence**: open each `*CommandHandler` or `handle` on the command side. Flag return types
  other than void, an id or a result status. Flag read-model or query-service calls inside.
- **Why it matters**: the write side now depends on read shapes. Each new screen changes a
  command, and the split stops paying for itself.
- **Fix**: return the new id or nothing, and let the caller send a query for the view.

## 7. CQRS: query handlers or read models that write

- **Check**: query handlers, read models or GET routes that insert, update, delete or
  publish events.
- **Evidence**: Grep query handler and read model files for `save`, `create`, `update`,
  `delete`, `insert`, `publish`, `dispatch`, `->increment`.
- **Why it matters**: reads become unsafe to retry or cache, replicas cannot serve them, and
  a write can happen outside the command side's rules. This is Critical when it writes
  domain state.
- **Fix**: move the write to a command, or to an async event if it is a counter or audit log.

## 8. CQRS: commands with no single handler

- **Check**: commands with no handler, or more than one, or handled by type checks in a big
  switch.
- **Evidence**: list every class in `Commands/`. Grep for each name in handler registrations
  or handler classes. Grep for `instanceof` or `switch` on command types.
- **Why it matters**: a command with no handler fails at runtime or is dropped silently. Two
  handlers run the change twice or in an unknown order.
- **Fix**: one handler per command, registered in one place, and a test that every command
  class resolves to exactly one handler.

## 9. CQRS: projections with no rebuild path

- **Check**: read models or projections built from events with no way to rebuild them from
  scratch.
- **Evidence**: Grep for projector or projection classes, then for a replay or rebuild
  command, job or script. Check that the projector can run twice without double-counting.
- **Why it matters**: a bug in a projector corrupts the read model forever. Without a
  rebuild, the only fix is hand-written SQL in production.
- **Fix**: add a rebuild command that truncates the read table and replays from the event
  store or source tables, and make projector updates idempotent (upsert by id and version).

## 10. CQRS: read and write models share a table with no reason

- **Check**: a "read model" that is the same table as the write model, or both sides mapping
  one table with different classes.
- **Evidence**: compare the table names in read model and write model classes or
  migrations.
- **Why it matters**: there is a split in code but not in data. It costs two models and gives
  none of the read-side gains.
- **Fix**: either give the read side its own table or view built for its screens, or drop
  the split and use one model.

## 11. CQRS: eventual consistency gaps the UI does not handle

- **Check**: the read side is updated async (queue, event bus, projector), but the UI reads
  it right after a write as if it were instant.
- **Evidence**: trace a create or update flow. Find the redirect or refetch after the command,
  and check whether the projection is updated in the same request or later.
- **Why it matters**: users save and then see old data, save again and create duplicates.
- **Fix**: return the new state from the command response for that screen, update the UI
  optimistically, or poll until the read model's version matches. Show a pending state.

## 12. CQRS used on simple CRUD

- **Check**: commands, queries, handlers and a bus for screens that only create, read, update
  and delete rows with no rules.
- **Evidence**: count handlers whose body is one ORM call. Count files touched to add one
  field to such a screen.
- **Why it matters**: each change costs four to eight files for no gain. New people copy the
  ceremony everywhere.
- **Fix**: keep CQRS where reads and writes really differ (complex rules, heavy read load,
  separate stores). Use plain controllers and models for the CRUD screens, and say which is
  which in `AGENTS.md`.

## 13. Hexagonal/DDD: domain imports framework or infra

- **Check**: domain or core code that imports the web framework, ORM, HTTP client, queue,
  mail or config.
- **Evidence**: Grep `Domain/`, `domain/`, `core/` for imports of `Illuminate\`, `django.`,
  `ActiveRecord`, `express`, `@nestjs/`, `org.springframework`, `javax.persistence`,
  `Microsoft.EntityFrameworkCore`, `database/sql`, `gorm`, `next/`, ORM clients and SDKs.
- **Why it matters**: the domain cannot be tested or moved without the framework, which is
  the whole reason for the pattern.
- **Fix**: define a port (interface) in the domain, implement it in infrastructure, and wire
  it in the container or composition root.

## 14. Hexagonal/DDD: anaemic models

- **Check**: entities that are only getters and setters, while every rule about them lives in
  services.
- **Evidence**: open the core entities. Count methods with rules against plain accessors.
  Grep services for repeated checks on one entity's fields (`status ==`, `->state`).
- **Why it matters**: the invariants are spread over many services, so one path forgets them.
- **Fix**: move each rule into the entity as a method that guards its own state, for example
  `order.cancel()` that refuses when shipped, and have services call it.

## 15. Hexagonal/DDD: aggregates reaching across boundaries

- **Check**: one aggregate holding object references to another, changing it, or one
  transaction saving several aggregates.
- **Evidence**: open aggregate classes and their repositories. Flag fields typed as other
  aggregates, calls that mutate them, and transactions that save more than one root.
- **Why it matters**: the boundary stops protecting anything. Concurrent edits clash and
  locks grow.
- **Fix**: reference other aggregates by id, and change them through a domain event and its
  own handler.

## 16. Hexagonal/DDD: ports with one adapter and no test double

- **Check**: interfaces with exactly one implementation and no fake, stub or in-memory version
  in tests.
- **Evidence**: list interfaces in `ports/`, `Contracts/`, `Interfaces/`. Grep for their
  implementations in `src` and in `tests`.
- **Why it matters**: the abstraction adds a file and a jump for every reader and buys
  nothing. This is over-abstraction.
- **Fix**: delete the interface and use the class, or add the in-memory adapter and use it in
  tests so the port earns its place.

## 17. Modules: import cycles between modules

- **Check**: module A imports module B and B imports A, directly or through a chain.
- **Evidence**: Grep each module's imports of other modules and build the edge list. Use
  the stack's tool output if it is already in the repo (deptrac, packwerk, madge, ArchUnit
  reports). Go refuses package cycles, so check module-level cycles only.
- **Why it matters**: the modules cannot be changed, tested or split apart alone.
- **Fix**: move the shared part to a third module both depend on, or invert one edge with an
  event or an interface owned by the caller.

## 18. Modules reading each other's tables

- **Check**: one module querying a table or model owned by another module.
- **Evidence**: map each table to its owning module (by migration folder or model location).
  Grep each module for model and table names owned by the others.
- **Why it matters**: the owner cannot change its schema without breaking callers it does
  not know about. It blocks any later split into services.
- **Fix**: call the owning module's public service or query, or have it publish the data the
  other module needs.

## 19. God classes and god files

- **Check**: files or classes that do too much.
- **Evidence**: classes with more than 20 public methods or constructors with more than 7
  dependencies, mixing jobs that belong to different layers or modules. File size and churn
  hot spots are `codebase-review`'s; here judge responsibilities only.
- **Why it matters**: every feature touches the same file. Merge conflicts, slow reviews and
  hidden coupling follow.
- **Fix**: split by responsibility along the seams the methods already show, for example
  `UserService` into `UserRegistration`, `UserProfile` and `UserBilling`. Name the new files.

## 20. Shared "utils" dumping grounds

- **Check**: `utils`, `helpers`, `common`, `shared`, `lib` folders or files that mix unrelated
  code and are imported everywhere.
- **Evidence**: list the folder. Count unrelated topics in one file and count importers.
- **Why it matters**: everything depends on it, so any change risks everything. Domain rules
  hide in it.
- **Fix**: move each function next to its only caller, or into a named module for its
  topic (`money`, `dates`). Keep only true generic helpers.

## 21. Circular service dependencies

- **Check**: services that inject each other, directly or through a chain.
- **Evidence**: read constructors or injected fields of core services. Grep for `forwardRef`
  (NestJS), `@Lazy` (Spring), late `require` inside functions (Node), or setter injection
  added to break a loop.
- **Why it matters**: the workaround hides the loop. Startup order and tests become fragile.
- **Fix**: extract the shared logic both need into a third service, or replace one call with
  an event.

## 22. Microservices: shared database

- **Check**: two or more services connecting to the same database or schema, or writing the
  same tables.
- **Evidence**: compare database names, connection env var names and migration folders
  across services. Read `.env.example` files only.
- **Why it matters**: there is no ownership. Two writers can corrupt each other's rows, and
  no service can change its schema alone. Critical when both write.
- **Fix**: give each table one owning service. Others read through its API or a replicated
  read model.

## 23. Microservices: chatty sync call chains

- **Check**: one request calling service A, then B, then C in sequence, or calling one
  service in a loop.
- **Evidence**: trace a core request across HTTP or gRPC clients. Grep for clients inside
  loops and for chains longer than two.
- **Why it matters**: latency adds up and availability multiplies down. Three services at
  99.9 percent give about 99.7 percent for the chain.
- **Fix**: batch the calls, cache stable data locally, or move the follow-up work to an async
  event.

## 24. Microservices: distributed monolith signs

- **Check**: services that must deploy together, share a domain library with entities, or
  break when one is down.
- **Evidence**: one deploy pipeline for all services, a shared package of domain models,
  lockstep version bumps in the git log, no timeouts or fallbacks on service clients.
- **Why it matters**: you pay the network cost of services and keep the coupling of a
  monolith.
- **Fix**: share contracts (schemas, generated clients), not entities. Add timeouts and
  fallbacks. If the services cannot be separated, merge them into a modular monolith.

## 25. Cross-cutting: configuration

- **Check**: where config is read. Flag env reads scattered across the code instead of one
  config layer.
- **Evidence**: Grep for `env(` outside `config/` (Laravel), `os.environ` outside settings,
  `process.env.` outside one config module, `System.getenv`, `os.Getenv`.
- **Why it matters**: defaults differ by caller, config caching breaks (Laravel returns null
  from `env()` once config is cached), and nobody knows the full list of settings.
- **Fix**: read env in one config module, validate it at boot, and inject or import values
  from there.

## 26. Cross-cutting: authentication and authorization

- **Check**: where auth is enforced. Flag a mix of middleware, guards, policies and hand-written
  checks in controllers for the same kind of route.
- **Evidence**: list routes and their middleware or guards. Grep controllers and handlers
  for inline `user.role`, `isAdmin`, `user_id ==` checks.
- **Why it matters**: when each route checks in its own way, one route forgets. Deep
  authorization bugs go to `app-security-review`.
- **Fix**: one mechanism per kind of check, for example route middleware for login and
  policies for ownership, and remove the inline copies.

## 27. Cross-cutting: error handling

- **Check**: where errors are caught and turned into responses. Flag mixed styles: some
  routes catch and return their own shapes, others rely on a global handler.
- **Evidence**: Grep for `try`, `catch`, `rescue`, `except` in controllers and handlers;
  find the global handler (`Handler.php`/`bootstrap/app.php`, `rescue_from`, exception
  middleware, `@ControllerAdvice`, NestJS filters, Next.js `error.tsx`).
- **Why it matters**: clients get different error shapes, and swallowed errors hide real
  failures.
- **Fix**: throw typed errors from the domain and services, map them in the one global
  handler, and remove local catches that only reformat.
