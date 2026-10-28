---
name: blog
description: Entry point for RayStack blog writing. Use for "/blog", "write a blog post", "what should I blog about", "draft a post", "set up my voice", or any request to pick a topic, draft a post in the author's voice, humanize it and make a cover.
---

# Blog

This skill runs the RayStack blog flow: pick a topic, draft it in your voice, humanize it and
make a cover. It stops at a draft. It never publishes, schedules, cross-posts or pushes.

| Skill | Does |
| --- | --- |
| `blog-topics` | Scores topic ideas and waits for your pick |
| `blog-draft` | Writes the post as a draft in your voice |
| `humanize` | Removes AI tells from the draft |
| `blog-cover` | Renders the cover image |

## 1. Find the voice file

Look for `.raystack/voice.md` at the repo root, then `~/.raystack/voice.md`. The repo file
wins. If found, read it and go to section 4.

## 2. No voice file

Ask through the host's question tool (AskUserQuestion in Claude Code; plain text only when the
agent has no such tool):

- "Set up my voice now (Recommended)": go to section 3.
- "Continue with a neutral voice": go to section 4 with no voice file.

Never fall back to another author's voice. `references/voice-example.md` is a worked example
only, never a voice to write in.

## 3. Set up the voice

1. Ask for 3-5 posts the user wrote: repo paths or URLs.
2. Read them. Fill [the template](references/voice-template.md) from what they actually do:
   openings, sentence length, words they avoid, formatting, closing, cover footer, topics.
   Quote their own lines where it helps. Don't invent rules the posts don't show.
3. List what the posts couldn't answer (often the cover footer `domain:` and `handle:`, the
   closing links and the ideas file). Ask in ONE question-tool call, max 4 questions total
   including the save location below: at most 3 gap questions (combine domain and handle into
   one). Any further gaps go in a second call. Leave any section the user skips as "not set".
4. In that same call, ask where to save it: `.raystack/voice.md` in this repo (Recommended) or
   `~/.raystack/voice.md` for every repo. Write it there.
5. Show [the worked example](references/voice-example.md) so the user can see a filled file,
   and say they can edit theirs any time.

## 4. Run the flow

Run these in order, one at a time. Pass the voice file path (or "neutral voice") to every step; each step uses it and doesn't ask again.

1. `blog-topics`. Stop and wait for the user to pick a topic. Don't start drafting on a default.
2. `blog-draft` with the picked topic.
3. `humanize` on the draft file.
4. `blog-cover` for the draft.

How to invoke each one:

- Claude Code: invoke the Skill tool with the name your agent lists it under (in a Claude Code
  plugin install this is `raystack:<name>`, e.g. `raystack:blog-draft`; a personal install
  uses the bare name).
- Other agents: read `../<skill>/SKILL.md` and follow it.

## 5. Stop

After the draft and the cover:

- List every file written: the post, the cover, and the voice file if setup ran.
- Say the post is a draft and has not been published.
- Don't publish, schedule, cross-post, commit or push. Those are the user's call.
