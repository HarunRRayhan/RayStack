# Project intake

The first step of `project new`, before `dev-hub` and research. Ask one question per call
through the question tool (the contract's Questions rule), recommended option first. Skip a
question that `DECISIONS.md`, the user's message or an earlier answer already settles.

1. **What are you building?** Web app, mobile app, API or backend service, CLI or library,
   desktop app, AI or agent product, other.
2. **Who is it for?** The user, and who pays if that is someone else.
3. **What problem does it solve?** One sentence, in the user's words.
4. **What must v1 do?** The three to five things without which it is not worth shipping.
5. **What must it never do?** Data it must not touch, actions it must not take.
6. **Limits:** deadline, budget, team size, stack the team already knows, hosting it must
   use, compliance (GDPR, HIPAA, SOC 2).
7. **Who else does this?** Competitors or tools the user knows of, or "not sure".
8. **How will you know it worked?** One measure: users, revenue, time saved.

If `DECISIONS.md` is missing, add it first from `../../dev-hub/assets/DECISIONS.md`.
Log each answer as a `D-` row right after it is given (`Decided`, today's date, "intake" as
the way to confirm). An answer of "not sure" becomes an `Open` row, never a guess.

When the questions are done, say in three lines what you heard (product, user, v1) and
which research notes come next: the market and competitors (from 2, 3 and 7) and the
technical options for the stack (from 1 and 6). Then run `dev-hub`, then `dev-research`. If
the user picks hub mode there, move the intake rows into the hub's `DECISIONS.md` and leave
a pointer in the repo.
`dev-prd` reads these rows and asks only what is still unknown.
