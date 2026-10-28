# <Review name>: <repo>

Date: YYYY-MM-DD. Skill: `<skill>`.

## Executive summary

- **Overall state:** <one or two sentences>
- **Top 3 risks:**
  1. <risk>
  2. <risk>
  3. <risk>
- **Total est. $/mo:** <sum of the findings below, or "n/a">

## Inputs used / missing

- **Used:** <IaC paths, CLI profile/account/DB, exported files>
- **Missing:** <input, and the export or command that would provide it>

## Findings

<!-- Rank Critical > High > Medium > Low; ties by est. $/mo, highest first.
     A finding not backed by real inputs gets " (unconfirmed)" at the end of its title. -->

### [Severity] <Title>

**Evidence**: <file:line, or the command plus an output excerpt>

**Why it matters**: <impact in plain words>

**Fix**:

```diff
<diff or IaC change, or a command for the human to run>
```

**Est. $/mo**: <amount with arithmetic, e.g. 3 x $30.37 = $91.11, or "n/a">

## Commands for you to run

<Commands the review could not or should not run itself, each with one line on why.>

```sh
<command>
```

---

Reviewed with RayStack by Harun R. Rayhan. For a hands-on audit: https://harun.dev/consultation
