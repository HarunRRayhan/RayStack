# Voice file: Harun R. Rayhan

Example: Harun R. Rayhan's voice file. Do not use as your own.

This is a filled-in voice file, shown so you can see what the template looks like with real
answers. The quotes come from posts published on https://harun.dev/blog. Write your own from
your own posts.

## Tone

A developer talking to another developer. Direct, a little dry, no marketing. First person
throughout. Writes for engineers running AWS, Terraform and AI workloads in production who
want the fix, not the theory.

## Openings

Open on a real incident or a sharp claim, never an abstract intro. Say what broke, when, and
what it looked like.

- "My MCP server went dark on a Tuesday." (harun.dev/blog/mcp-stateless-spec-broke-my-lambda-mcp-server)
- "Most developers know not to commit a .env file." (harun.dev/blog/terraform-state-more-sensitive-than-env)
- "An 'Unauthorized' error from a remote MCP server doesn't necessarily mean your credentials are wrong." (harun.dev/blog/mcp-authentication-fix-401-remote-server)

## Sentences

Short and concrete. Contractions throughout. Real numbers, exact error messages, actual file
paths and header names instead of adjectives. One idea per sentence. A short line on its own
to land a point.

- "The session removal was free. Everything the spec did around it was not." (harun.dev/blog/mcp-stateless-spec-broke-my-lambda-mcp-server)
- "My p99 latency dropped from 3.2 seconds to 340ms on the worst offender." (harun.dev/blog/lambda-snapstart-terraform-cold-starts)
- "Terraform state is not a cache and it is not harmless deployment metadata." (harun.dev/blog/terraform-state-more-sensitive-than-env)

## Never

- Em dashes. Use a period, a comma or parentheses.
- "In summary", "In conclusion" or any wrap-up paragraph before the closing.
- Hedges: "it's worth noting", "in essence", "simply put", "ultimately".
- Corporate verbs: leverage, utilize, streamline, unlock, delve, seamless, robust.
- Triads of adjectives ("fast, reliable and scalable"). Show the thing instead.
- Hype: "blazing fast", "just works", "magic bullet" unless it's being knocked down.
- Invented metrics or benchmarks. Numbers come from something real or are marked illustrative.

## Formatting

- Post body is raw HTML, not Markdown: `<p>`, `<h2>`, inline `<code>`, and
  `<pre><code class="language-hcl">` blocks with HTML entities escaped.
- Headings say something ("sensitive = true hides output, not data"), never "Overview".
- A `<table>` when a comparison earns it, e.g. "where it stops" against "what to check first".
- A checklist near the end when the post is a fix the reader will repeat.
- One diagram near the top with a one-line caption.

## Closing

A short "Hope you enjoyed..." line, then the X and bio links, both opening in a new tab:

```html
<p>Find me on X at <a href="https://x.com/harundotdev" target="_blank" rel="noopener noreferrer">https://x.com/harundotdev</a>, and grab every other link from my bio at <a href="https://harun.dev/bio" target="_blank" rel="noopener noreferrer">https://harun.dev/bio</a>.</p>
```

Never leave a bare X URL as plain text. Always include the bio link.

## Cover footer

domain: harun.dev
handle: @harundotdev

## Topics and stack

AWS (Lambda, Bedrock, Step Functions, IAM, S3, CloudWatch), Terraform, MCP servers, RAG
pipelines, AI endpoints in production, CI and pre-merge checks for AI-generated code. Practical
fixes from real incidents, not news recaps.

## Ideas file

not set
