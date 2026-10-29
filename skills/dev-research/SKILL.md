---
name: dev-research
description: Write dated research notes with a source beside every fact, for market, competitors or technical options. Use for "research the market", "compare these options", "who else does this", or when dev reaches the research step.
---

# Dev research

This skill turns a question into a note in `docs/research/`. Formats, IDs and question
rules are in `../dev/references/dev-contract.md`.

## 1. Check the tool first

You need a web search or page-fetch tool from the host. If there is none, say so in one
line and stop. Do not write notes from memory: a note with no sources is worse than none.
Offer to resume when the user can pass in pages, files or links to read.

## 2. Scope the question

Read `DECISIONS.md` and the existing `docs/research/` first. Do not redo a settled
question. If the topic is unclear, ask through the question tool, at most 5 questions,
recommended option first. Typical scopes:

- **Market**: who buys, what they pay, what they use now.
- **Competitors**: what each does, what it costs, what it explicitly does not do.
- **Technical options**: the real choices, their limits, how mature each one is.

One note per topic. Split a broad ask into several notes.

## 3. Gather and record

- Prefer primary pages: vendor docs, pricing pages, changelogs, filings, repos.
- Put a source beside every fact: a URL in the same table row or bullet. A fact with no
  link does not go in.
- Mark a claim `unverified` when it comes from one third-party page, a forum post or a
  press summary, or when you could not open the page. Keep it, label it, and link it.
- Give dates for anything that changes: prices, versions, funding, launch dates.
- Where sources disagree, show both and say which you trust and why.
- Copy no long passages. Paraphrase and link.

## 4. Write the note

Save `docs/research/YYYY-MM-DD-<topic>.md` with today's date:

```
# <Topic>, <Month YYYY>

## Question
One or two lines: what this note answers and why.

## Findings
Tables or bullets. A source beside every fact. `unverified` where it applies.

## Gaps
What you could not find or confirm.

## What this means for the product
3 to 6 bullets: what to build, avoid or test, tied to the findings. No new facts here.
```

Never edit an old note. If a fact changed, write a new dated note and link the old one.

## 5. Finish

Tell the user the file path, the three strongest findings and the biggest gap. If a
finding settles a choice, propose a `D-` row for `DECISIONS.md` and ask before adding it.
Then hand back to `dev`, usually for `dev-prd`.
