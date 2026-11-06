---
name: rs
description: Short alias for /raystack, the entry point for everything in RayStack. Use for "/rs", "/rs refactor", "/rs scan all", "/rs project new", "/rs build", "/rs review", "/rs update", or any request that starts with rs followed by a RayStack job.
---

# rs

`/rs` is `/raystack` with a shorter name. It has no logic of its own: hand the user's words
to `raystack` unchanged and stop. `/rs refactor` runs `/raystack project refactor`.

Claude Code: invoke the Skill tool with the user's words in the args, by the name your agent
lists (`raystack:raystack` in a plugin install, else `raystack`). Other agents: read
`../raystack/SKILL.md` and follow it.
