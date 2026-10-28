---
name: humanize
description: Rewrite AI-sounding prose so it reads like a person wrote it. Use on blog drafts, READMEs, docs and release notes, or when text has AI tells (em dashes, triads, hedging, stacked adjectives, corporate tone).
---

# Humanize

Rewrite the text so a person could have typed it. Keep the meaning.

## Steps

1. Look for a voice file: `.raystack/voice.md` at the repo root, else `~/.raystack/voice.md`. The repo file wins. If found, read it. Its rules override the checklist wherever they conflict.
2. If the caller passed a voice file path or "neutral voice", use it and don't ask. No voice file: use [the checklist](references/checklist.md) alone. Never borrow another author's voice.
3. Rewrite in place. Keep the facts, numbers, code blocks, commands, paths and links exactly as they are. Don't add claims.
4. Report the number of edits you made, and anything you left alone on purpose.

## If you need to ask

Use the host's question tool (AskUserQuestion in Claude Code). Ask in plain text only when the agent has no question tool.

## Don't

- Flatten a document that already has a voice. Match it.
- Delete real information to hit a shorter length.
- End with a summary paragraph.
