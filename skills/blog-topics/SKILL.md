---
name: blog-topics
description: Score blog topic ideas from repo lessons, current news and the ideas file, show the top 10 and wait for the user's pick. Use for "what should I blog about", "give me post ideas" or as step 1 of the blog skill.
---

# Blog topics

Find topics worth a post, score them and let the user pick. This skill never drafts.

## 1. Read the voice file

Look for `.raystack/voice.md` at the repo root, then `~/.raystack/voice.md`. The repo file
wins. Use its `## Topics and stack` and `## Ideas file` sections. If the caller passed a voice file path or "neutral voice", use it and don't ask. No voice file: ask once
through the question tool to run setup via the `blog` skill or continue in a neutral voice.
Never borrow another author's voice.

## 2. Gather candidates

- **Repo lessons:** CLAUDE.md, AGENTS.md, `docs/`, and `git log` subjects for fixes and
  incidents. Each real bug, outage or hard-won rule is a candidate.
- **News:** web search for recent releases, changes and incidents in the voice file's stack.
- **Ideas file:** the path in `## Ideas file`, else `post-ideas.md` at the repo root if present.

Repo lessons from private or client code become generic lessons with no names: no company,
client, product, person or internal service.

## 3. Check freshness

Read the titles of the published posts. Drop or reshape a candidate the user already covered.

## 4. Score

Score each candidate 1-10 on four criteria, equal weights, and average them:

| Criterion | High score when |
| --- | --- |
| Stack fit | It is in `## Topics and stack` and the user knows it first-hand |
| Freshness | No published post covers it |
| News timing | It is tied to something that changed recently |
| Practical angle | A reader can apply it the same day |

## 5. Show the top 10

A table sorted by score: number, score, title, one-line angle. Then ONE question-tool call
(AskUserQuestion in Claude Code; plain text only when there is no question tool): pick a
number, or type a custom title.

## Rules

- Never draft in the same turn. Stop after the question and wait for the answer.
- Don't pick a default topic for the user.
- Don't invent news. Every news item comes from a search result you can link.
