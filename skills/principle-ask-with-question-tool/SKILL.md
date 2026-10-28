---
name: principle-ask-with-question-tool
description: Apply when you need a decision, approval, missing input or clarification from the user. Ask through the host agent's native question tool with batched, self-contained questions and a recommended option first.
---

# Ask With the Question Tool

A question the user can answer with one click gets answered faster and more precisely than a paragraph.

## Before asking

- Don't ask what you can find out. Read the repo, the config, the docs and the installed tools first.
- Ask only what blocks the next step. Keep working on everything that doesn't depend on the answer.

## How to ask

- Use the host agent's native question tool: AskUserQuestion in Claude Code, its equivalent elsewhere. Write plain text only when no such tool exists.
- Batch related questions into one call, at most 4. If one answer changes what you would ask next, ask that one alone first.
- Give each question 2 to 4 options. Put the recommended option first and end its label with "(Recommended)".
- Give each option a one-line reason tied to what you found, e.g. "Found 3 workflows in `.github/`".
- Make each question self-contained. The user may read it cold, without your earlier messages.

## After the answer

- Act on it. Don't ask the same thing again in other words.
- If the user declines or picks nothing, stop that path and say so.
