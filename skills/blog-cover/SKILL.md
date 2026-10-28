---
name: blog-cover
description: Render a blog post cover image as a self-contained HTML card (title, badges, footer) with headless Chrome. Use for "make a cover", "cover image for this post", or as step 4 of the blog skill. No AI images, no stock photos.
---

# Blog cover

Build one cover image for a draft post. Local only: never AI image generation, never
stock-photo fetching.

## 1. Find existing covers

- Look for images next to the posts, or the path the draft's cover frontmatter key points to.
- Read 2-3 of them to get size, layout, colours and footer. Keep their size unless told
  otherwise. No existing covers: use 1600x840.

## 2. Choose a base

- Covers exist: write a self-contained HTML file that matches them.
- None: copy `assets/cover-template.html` from this skill's folder and fill it. Its
  placeholders are `{{TITLE}}`, `{{BADGES}}`, `{{FOOTER_LEFT}}`, `{{FOOTER_RIGHT}}`, and the
  gradient is the CSS vars `--c1 --c2 --c3`.

## 3. Build it

- HTML-escape the title, badge labels and footer text before they go into the file.
- Badges: inline SVG icons or plain text labels. No remote URLs (images, fonts, CSS): the
  render blocks them, and only `data:` URIs load.
- Pick gradient colours that differ from the previous post's cover.
- Footer: read `## Cover footer` (`domain:` and `handle:`) from `.raystack/voice.md` at the
  repo root, else `~/.raystack/voice.md`. The repo file wins. If the caller passed a voice file path or "neutral voice", use it and don't ask. A value
  of `not set` or no voice file: ask once through the question tool, and use the answer.
- Photo background: only from an image the user supplies, inlined as a `data:` URI behind a
  dark overlay so the title stays readable.

## 4. Render

- Write the HTML to a temp file outside the repo.
- Run `scripts/render-cover.sh` from this skill's folder, as an absolute path:
  `<this skill's folder>/scripts/render-cover.sh <cover.html> <out.jpg> [WIDTHxHEIGHT]`.
  It needs Chrome and node, prints the written path, and writes PNG with a warning when it
  can't make a JPEG. If it exits 1 for a missing tool, tell the user which one.
- Save to the repo's cover convention, else beside the draft as `cover.jpg`.
- Use the path the script prints as the saved file: it may be a `.png` when no JPEG tool exists.
- If the draft has a cover frontmatter key, set it to that printed path in the repo's format.

## 5. Check

Read the image file and look at it before reporting: title fits and is not clipped, text is
readable, footer is right, nothing is blank. Fix the HTML and render again if not.

## 6. Report

The printed cover path, the size, and any frontmatter key you changed.

## Questions

Ask through the host's question tool (AskUserQuestion in Claude Code). Ask in plain text only
when the agent has no question tool.
