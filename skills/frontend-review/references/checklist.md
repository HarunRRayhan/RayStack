# Frontend checklist

Each item: **Check**, **Evidence** (Grep = code search with the agent's search tool; Read =
open the file and follow the code), **Why it matters**, **Fix**. Placeholders are UPPERCASE.
Replace them with literal values before running.

Every finding cites file:line. Do not run package scripts, builds or tests. Read build
output only if it already exists.

## 1. Oversized components

- **Check**: components over about 300 lines, or one component that fetches data, holds
  state and lays out the page at once.
- **Evidence**: list the largest files in the component and page folders (`wc -l` on
  `*.tsx`, `*.jsx`, `*.vue`, `*.svelte`, `*.component.ts`). Read the top ones for fetch
  calls, many `useState`/`ref`/`$state` lines and long markup in the same file.
- **Why it matters**: big mixed components are hard to test, re-render as one block and
  break in many places when one part changes.
- **Fix**: split into a data part (hook, composable, loader or service) and presentational
  children. Name the split, for example `useInvoices()` plus `InvoiceTable` and
  `InvoiceFilters`.

## 2. Prop drilling

- **Check**: the same prop passed through more than 3 levels of components that do not use
  it.
- **Evidence**: pick a prop from a page (user, theme, locale, permissions). Grep its name
  across components and follow the chain. Count the levels that only pass it on.
- **Why it matters**: every middle component changes when the prop changes, and the chain
  breaks easily in refactors.
- **Fix**: use context (React), `provide`/`inject` (Vue), context or stores (Svelte), a
  service (Angular), or Inertia shared props via `usePage()`. Or move the component closer to
  where the data lives.

## 3. Duplicated components

- **Check**: two or more components that render the same thing with small changes (buttons,
  modals, cards, tables, date pickers).
- **Evidence**: Grep for repeated names (`Modal`, `Button`, `Card`, `Table`) in more than
  one folder. Read pairs and compare the markup.
- **Why it matters**: fixes and accessibility work land in one copy and not the other.
- **Fix**: keep one component with a prop for the difference. Delete the other and update
  its imports.

## 4. Server state in a global client store

- **Check**: API data copied into Redux, Zustand, Pinia, Vuex, NgRx or a Svelte store, with
  hand-written loading flags and no refetch.
- **Evidence**: Grep store files for `fetch(`, `axios`, `isLoading`, `setItems`. Read where
  the store is filled and when it is refreshed.
- **Why it matters**: the copy goes stale, every page re-implements loading and errors, and
  data from one user can stay after sign-out.
- **Fix**: move server data to a query cache (TanStack Query, SWR, RTK Query, Nuxt
  `useFetch`, SvelteKit `load`, Inertia props). Keep the global store for UI state only.

## 5. Unsafe fetch in effects

- **Check**: `fetch` or `axios` inside `useEffect`, `onMounted` or `ngOnInit` with no cancel,
  no error state or no loading state.
- **Evidence**: Grep `useEffect`, `onMounted`, `ngOnInit`, `onMount` and read the bodies for
  `fetch(`, `axios.`, `.subscribe(`. Look for `AbortController`, an `ignore` flag,
  `takeUntil`/`takeUntilDestroyed`, a `catch` and a loading flag.
- **Why it matters**: with no cancel, a slow old response can overwrite a newer one, and
  setting state on an unmounted component leaks. With no error state, a failure shows a
  blank or stuck page.
- **Fix**: use the query library or the framework loader. If the effect stays, add an
  `AbortController` and abort it in the cleanup, and render loading and error states.

## 6. Fetch waterfalls

- **Check**: sequential fetches that do not depend on each other, or parent and child
  components that each fetch on mount, one after the other.
- **Evidence**: read loaders and effects for `await` lines in a row with no data passed
  between them. Read page trees where a child fetches only after the parent has rendered.
- **Why it matters**: the page waits for the sum of the calls, not the longest. Three 300 ms
  calls in a row take about 900 ms instead of about 300 ms.
- **Fix**: run independent calls with `Promise.all`, hoist fetches into the route loader or
  server component, or prefetch the child data with the parent.

## 7. No cache or dedupe

- **Check**: the same endpoint fetched by several components on one page, or fetched again
  on every mount, with no shared cache.
- **Evidence**: Grep the endpoint path (`/api/ME`, `/api/user`) across components. Check
  for TanStack Query, SWR, Apollo, RTK Query, Nuxt `useFetch` keys, SvelteKit `load` or
  Next.js `fetch` cache options.
- **Why it matters**: duplicate calls slow the page and load the server for no gain.
- **Fix**: add a query library with shared keys, or load once in the route loader and pass
  it down. In Next.js set `cache` or `revalidate` on server fetches.

## 8. Stale closures

- **Check**: callbacks, intervals or listeners that read state captured at an old render.
- **Evidence**: Grep `setInterval`, `addEventListener`, `useCallback`, `useMemo` and
  `useEffect` with `[]` deps whose body reads props or state. Check for disabled lint rules
  (`eslint-disable` with `react-hooks/exhaustive-deps`).
- **Why it matters**: the handler acts on old values, so counters stop, forms send old data
  and filters ignore the latest choice.
- **Fix**: add the missing dependencies, use the functional update (`setX(x => x + 1)`), or
  keep the latest value in a ref. Remove the lint disable.

## 9. Unnecessary re-renders

- **Check**: inline objects, arrays or functions passed to memoised children; a context
  provider whose `value` is a new object each render, or one context holding unrelated
  values.
- **Evidence**: Grep `React.memo`, `memo(` and read the parents for `style={{`,
  `options={[`, `onX={() =>`. Grep `Provider value={{` and `createContext`. In Vue, look for
  big reactive objects passed whole as props. In Angular, check for `ChangeDetectionStrategy`.
- **Why it matters**: the memo never holds, and every consumer of a wide context re-renders
  on any change. On big lists and forms this causes input lag.
- **Fix**: wrap the value in `useMemo`/`useCallback`, split the context by concern, or move
  state down to the component that uses it. In Angular use `OnPush` and `trackBy`.

## 10. List keys

- **Check**: lists with no key, or with the array index as key, where items can be added,
  removed or reordered.
- **Evidence**: Grep `.map(` in JSX for `key=` and `key={i}`, `key={index}`. Grep `v-for`
  for `:key`, `{#each` for `(item.id)`, `*ngFor` and `@for` for `trackBy` or `track`.
- **Why it matters**: index keys attach state to the wrong row after an insert or delete, so
  inputs show the wrong values and animations jump.
- **Fix**: key by a stable id from the data, for example `key={item.id}`.

## 11. Long lists with no virtualisation

- **Check**: tables or lists that render hundreds or thousands of rows at once.
- **Evidence**: Read list pages for full-array `.map` or `v-for` over API data with no
  pagination. Check `package.json` for `react-window`, `@tanstack/react-virtual`,
  `vue-virtual-scroller`, `@angular/cdk/scrolling`.
- **Why it matters**: thousands of DOM nodes make first render, scroll and typing slow,
  most on phones.
- **Fix**: paginate, or render only visible rows with a virtual list.

## 12. Layout shift

- **Check**: images, embeds, ads or late content with no reserved space; skeletons that
  differ in size from the real content.
- **Evidence**: Grep `<img`, `<iframe`, `<video` for `width` and `height` or an
  `aspect-ratio` class. Read loading states against the loaded markup.
- **Why it matters**: content jumps while users read or tap, causing wrong clicks, and CLS
  hurts search ranking.
- **Fix**: set `width` and `height` or `aspect-ratio`, reserve space for late content, and
  match the skeleton size to the real one.

## 13. Next.js: "use client" too high

- **Check**: `"use client"` on layouts, pages or wrappers near the root, which turns the
  whole subtree into client code.
- **Evidence**: Grep `use client` under `app/`. Read each hit in a `layout.*` or `page.*`
  and note what in it needs the client (state, effects, browser APIs).
- **Why it matters**: server-only work and data move into the client bundle, so more JS
  ships and data is fetched in the browser instead of on the server.
- **Fix**: keep the page a server component and move only the interactive part into a small
  client component. Pass server components as `children` to client wrappers.

## 14. Secrets in client code

- **Check**: API keys, tokens or private URLs in client components, in `NEXT_PUBLIC_`,
  `VITE_`, `NUXT_PUBLIC_` or `PUBLIC_` env names, or in Inertia shared props.
- **Evidence**: Grep `NEXT_PUBLIC_`, `VITE_`, `NUXT_PUBLIC_`, `PUBLIC_`, `import.meta.env`
  and `process.env` in client files. Read `.env.example` for names only. Grep Inertia
  `share(` (Laravel `HandleInertiaRequests`) for keys, tokens and full user models. Report
  names, never values.
- **Why it matters**: anything in the client bundle or page props is public. A secret key
  there is exposed to every visitor. This is Critical when the name is a secret.
- **Fix**: keep the secret server-side, call the third party from a route handler, server
  action or backend endpoint, and rotate the exposed key. Point to `app-security-review`.

## 15. Next.js and SvelteKit: no loading or error boundaries

- **Check**: route segments with data fetching and no `loading.*` or `error.*` file; no
  `not-found.*`; SvelteKit routes with no `+error.svelte`; Nuxt with no `error.vue`.
- **Evidence**: list the route folders under `app/` or `src/routes/` and check for the
  boundary files next to `page.*` and `+page.*`.
- **Why it matters**: a slow fetch shows nothing, and a thrown error blanks the whole page
  or the whole app.
- **Fix**: add `loading.tsx` and `error.tsx` (a client component with a retry button) to
  segments that fetch. Add `+error.svelte` or `error.vue` at the root.

## 16. Accessibility basics

- **Check**: images with no `alt`; `div` or `span` with click handlers; inputs with no
  label; `outline: none` with no focus style; colour as the only cue; modals with no focus
  trap or no Escape; headings that skip levels or a page with no `h1`.
- **Evidence**: Grep `<img` and `<Image` with no `alt`; `<div onClick`, `<span onClick`,
  `@click` on `div`; `<input` with no `<label`, `aria-label` or `id` pair; `outline-none`,
  `outline: none` with no `focus-visible`; `role="dialog"` and modal components for a focus
  trap (`focus-trap`, Radix, Headless UI, native `<dialog>`); `<h1` to `<h6` order per page.
  Check `package.json` for `eslint-plugin-jsx-a11y` or `vuejs-accessibility`.
- **Why it matters**: keyboard and screen reader users can't reach or understand the control.
  On a core flow that blocks them, which is High. Some markets require it by law.
- **Fix**: add `alt` (empty for decoration), use `<button>` or `<a>`, link every input to a
  `<label>`, add `focus-visible` styles, add text or an icon next to colour cues, use a
  dialog that traps focus and closes on Escape, fix heading order. Add the a11y lint plugin.
  This list is a floor. Recommend a full WCAG audit with real assistive tech.

## 17. Form validation and errors

- **Check**: no client validation that mirrors the server rules; errors shown only at the
  top or in a toast, not next to the field; field errors not linked to inputs.
- **Evidence**: Read the core forms. Look for a schema (`zod`, `yup`, `valibot`,
  `vee-validate`, Angular `Validators`) or `required`, `type`, `pattern` attributes. Check
  how server errors render (Inertia `form.errors.FIELD`, `errors.FIELD`). Grep
  `aria-invalid` and `aria-describedby`.
- **Why it matters**: users submit, wait and then hunt for what was wrong. Screen readers
  do not announce errors that are not linked to the field.
- **Fix**: share or mirror the server rules in a client schema, render each error under its
  field with `aria-invalid` and `aria-describedby`, and keep the server check as the
  source of truth.

## 18. Double submit

- **Check**: submit buttons that stay active while the request runs, or handlers with no
  in-flight guard.
- **Evidence**: Read submit handlers and buttons for `disabled={processing}`,
  `form.processing` (Inertia), `isPending`, `isSubmitting`. Note payment and create
  endpoints with no idempotency key.
- **Why it matters**: a double click sends two orders, two payments or two sign-ups.
- **Fix**: disable the button and show progress while the request runs, ignore a second
  submit in the handler, and send an idempotency key on payment and create calls.

## 19. No error boundary

- **Check**: no React error boundary (or framework equivalent) around the app or risky
  widgets; no global error handler.
- **Evidence**: Grep `componentDidCatch`, `ErrorBoundary`, `react-error-boundary`,
  `app.config.errorHandler` (Vue), `ErrorHandler` (Angular), `handleError` (SvelteKit
  hooks).
- **Why it matters**: one thrown error in a widget unmounts the whole app and shows a blank
  page, with no report sent.
- **Fix**: wrap the app and each risky widget in an error boundary with a fallback and a
  retry, and send the error to the existing error tracker.

## 20. Heavy dependencies, images and fonts

- **Check**: `moment`, whole `lodash`, full icon sets, no route splitting, unsized or eager
  images, blocking fonts.
- **Evidence and fix**: run `performance-review` checklist items 8 and 9; here, only note the
  hits with file:line and point to that report.

## 21. SEO basics on public pages

- **Check**: public pages with no unique title, meta description or canonical; public
  content rendered only in the browser where search matters.
- **Evidence**: Grep `<title`, `<Head`, `useHead`, `export const metadata`,
  `generateMetadata`, `svelte:head`, Angular `Title` and `Meta`. Check for
  `rel="canonical"`. For a client-only app (Vite SPA, Inertia without SSR), check whether
  the server template sets these tags in the first response.
- **Why it matters**: missing or duplicate titles and canonicals lower ranking and click
  rate. Content that needs JS may be indexed late or badly.
- **Fix**: set title, description and canonical per public page in the framework head API
  or the server template. Use SSR, SSG or prerender for public content pages. Skip private
  pages.

## 22. Unsafe HTML and tokens in the client

- **Check**: `dangerouslySetInnerHTML`, `v-html`, `{@html}`, `[innerHTML]` or
  `bypassSecurityTrust*` with data a user can set; auth tokens in `localStorage` or
  `sessionStorage`.
- **Evidence**: Grep those names and trace the value back to its source. Grep
  `localStorage.setItem` and `sessionStorage.setItem` for `token`, `jwt`, `auth`.
- **Why it matters**: user HTML rendered raw is stored XSS, and any XSS can read a token in
  storage and take over the account. This is Critical when user data reaches it.
- **Fix**: render as text, or sanitise with DOMPurify before rendering. Keep session
  tokens in `HttpOnly`, `Secure`, `SameSite` cookies. Point to `app-security-review`.

## 23. No tests for critical flows

- **Check**: no component or end-to-end test for sign-in, sign-up, checkout or the main
  form.
- **Evidence**: Grep for test files (`*.test.*`, `*.spec.*`, `e2e/`, `cypress/`,
  `playwright.config.*`) and read whether any covers the core flows. Check CI config for a
  frontend test step.
- **Why it matters**: a broken core flow ships without anyone noticing until users complain.
- **Fix**: add one end-to-end test per core flow (Playwright or Cypress) and run it in CI.
  Name the first test to write.
