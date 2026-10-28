---
name: blog-draft
description: Write a blog post as a draft in the author's voice, in the repo's own post format. Use after a topic is picked, for "draft a post about X", or as step 2 of the blog skill. Never publishes.
---

# Blog draft

Write one post as a draft file. Never publish, schedule, cross-post or push, and never run a
repo's publish command.

## 1. Before writing

- Read the voice file: `.raystack/voice.md` at the repo root, else `~/.raystack/voice.md`. The
  repo file wins. No voice file: ask once through the question tool to run setup via the
  `blog` skill or continue in a neutral voice. Never borrow another author's voice.
- Read 2-3 recent posts for voice, length and structure.

## 2. Detect the format

1. Find the posts folder: common paths (`posts/`, `content/posts/`, `content/blog/`,
   `src/content/blog/`, `_posts/`), plus any folder that holds
   several `.md` or `.mdx` files with a `title` in their frontmatter.
2. More than one candidate: ask which folder through the question tool.
3. None: write plain Markdown at `posts/<slug>.md` with `title`, `slug`, `description`,
   `date`, `tags` and `draft: true`.
4. Otherwise copy the frontmatter keys and the body format (Markdown, MDX or HTML) of the
   newest post. Fill every key it has.

## 3. Draft state

- Use the repo's draft mechanism: a `draft` flag, a drafts folder, a status field.
- Some repos publish any draft whose date has passed. Look for a scheduler or publish command
  (cron entries, scheduled jobs, CI workflows, scripts that read the date). If you find one,
  set a future date so the draft can't go live on its own.
- Never publish, and never run that command.

## 4. Write

- Open from a real incident the user or the repo provides. Never invent incidents, numbers
  or quotes. If there is none, ask once, or open from the problem itself.
- Repo lessons from private or client code become generic lessons with no names.
- Code examples use neutral names (`orders`, `fetchUser`, `app`), never project-derived
  prefixes.
- Follow `## Never` and `## Formatting` in the voice file.
- End with the voice file's `## Closing`, exactly as written there. No voice file: end on the
  last useful point, no summary.

## 5. Before saving

Run [the humanize checklist](../humanize/references/checklist.md) over the draft and fix what
it finds. The voice file wins where they conflict.

## 6. Report

- The path of the draft file.
- How to preview it, if the repo has a preview (a dev server route, a draft URL, a build
  command). Say so if there is none.
- That it is a draft and has not been published.

## Questions

Ask through the host's question tool (AskUserQuestion in Claude Code). Ask in plain text only
when the agent has no question tool.
