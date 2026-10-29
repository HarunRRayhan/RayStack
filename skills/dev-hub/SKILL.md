---
name: dev-hub
description: Set up the project layout for the RayStack dev flow, with AGENTS.md, DECISIONS.md and the docs folders, in one repo or in a code-free hub across repos. Use for "set up the dev flow", "start a project hub", "add DECISIONS.md", or when dev finds no hub.
---

# Dev hub

This skill gives a project the files the other `dev-*` skills read and write. It adds
files and never replaces one. Formats are in `../dev/references/dev-contract.md`.

## 1. Pick the mode

Ask once, through the question tool, with the recommended option first:

- **single-repo** (default): the product lives in one repo. Add the layout inside it.
- **hub mode**: the product spans several repos. Make a new folder that holds all
  knowledge and no code. Code repos keep a short pointer back to it.

## 2. Single-repo mode

1. Add `AGENTS.md` from `assets/AGENTS.md`. Fill every `<PLACEHOLDER>` from what you can
   read in the repo or by asking. Delete each block between `<!-- hub-only -->` and
   `<!-- /hub-only -->`, markers included. The rest is correct for a repo that holds code.
2. Add `DECISIONS.md` from `assets/DECISIONS.md`. It is the header row only.
3. Create `docs/research/`, `docs/prd/`, `docs/architecture/`, `docs/tech-spec/` and
   `docs/plans/`. Add a `.gitkeep` to any that stays empty.
4. Copy `../dev/references/principles.md` to `docs/principles.md`.

## 3. Hub mode

1. Ask through the question tool for the product name, the hub folder path and the code repos (name and path).
2. Create the hub folder. Run `git init` there. It is a local repo with no remote. Add a
   remote or a GitHub repo only if the user asks.
3. Put the same files in it as in single-repo mode, but keep the `hub-only` blocks (delete
   only the marker lines) and fill in the Repositories table.
4. For each code repo the user names, write `assets/AGENTS-pointer.md` as its instruction
   file, filled in with the hub path. If that repo already has instructions, follow the
   existing-file rules below.
5. One plan and one ledger live in the hub. Each code repo gets its own branch or
   worktree, its own reviews and its own PR, and ships on its own.

## 4. Existing-file rules

This skill never overwrites. Check each target before writing.

- `AGENTS.md` exists: append a `## RayStack dev flow` section with the reading order,
  the binding rules and the workflow from the template, with the hub-only blocks removed
  unless this is hub mode. Say you did.
- Only `CLAUDE.md` exists: append the same section there.
- Neither exists: create `AGENTS.md`. On Claude Code also create a one-line `CLAUDE.md`
  that holds `@AGENTS.md`, so both tools read the same file.
- `DECISIONS.md` or a `docs/` file exists: keep it and skip that step. If it uses other
  columns, keep them and tell the user, do not rewrite its rows.
- A pointer target exists: append the pointer as a section, do not replace the file.
- When a template goes into an existing file as a section, demote every heading one
  level (`#` to `##`, `##` to `###`) so the file keeps one H1.

## 5. Finish

List what was created, what was appended and what was skipped. Show the placeholders
still unfilled. Then hand back to `dev` for the next step, usually `dev-research`.
