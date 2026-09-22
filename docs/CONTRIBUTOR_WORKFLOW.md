# Contributor workflow

Use this workflow on both machines before making project changes.

## Step 1 — before you write anything

1. Read `PROJECT_STATE.json` at the repository root.
2. Read the file named in its `readme` field.
3. Identify:
   - Current phase and step, with the step title
   - Current owner, and which machine that owner is on
   - The top entry of `next_actions` and its acceptance sentence
   - Any contract listed as `draft` or `changing`
   - Any entry in `do_not_touch` that the request would have touched
   - Any `open_risks` relevant to this step
4. Resolve unclear scope or ownership with the responsible engineer before coding.

## Step 2 — the ten rules

1. Work only on the top entry of `next_actions` unless told otherwise.
2. Never edit a path listed in `do_not_touch` — not to fix a bug, not to make a
   test pass, not as a convenience.
3. Treat a frozen contract as immutable. If the task seems to need a new field,
   produce a contract pull request instead of inventing it.
4. Never invent product facts: no endpoints, screens, metrics, supplier names,
   review counts or copy that is not in the manual or the repository.
5. Apply the design bans: no purple-to-blue gradients, no gradient hero text, no
   pill buttons, no glassmorphism, no emoji in headings, no untouched component
   kit defaults, no fake reviews, metrics, counters or stock imagery. This
   applies to throwaway prototypes too.
6. Apply the security rules: server-side authorization on every route, strict
   schema validation, parameterised queries, no secret in a client bundle, no
   token, phone number or precise coordinate in a log line.
7. Every user-visible surface needs loading, empty, error, offline,
   permission-denied and success states.
8. Every retryable mutation needs an idempotency key.
9. Update `PROJECT_STATE.json` in the same change. A change that does not move
   the state is not finished.
10. Mark a gate passed only with actual engineer approvals, verification evidence
    and accepted deferrals; do not infer approval from a merged PR.

## Step 3 — include in the handoff

- What you did **not** do
- What is untested, and exactly which test would cover it
- What you assumed that the manual does not settle

## Review boundaries

| Request | Response |
|---|---|
| "Add the field now, update the contract later" | Refuse. Produce the contract PR. |
| "Mock the supplier reply in the app" | Refuse in app code. Put it in `/fixtures`. |
| "Skip the error states for now" | Refuse. The state matrix is the definition of done. |
| "Turn off the auth check while we test" | Refuse. Use a test identity or a staging flag. |
| "Put the API key in the frontend, it's only staging" | Refuse. Staging keys reach real providers. |
| "Make the empty state look fuller with sample data" | Refuse. Design an honest empty state. |
| "Mark the phase done, the code is merged" | Refuse. Name the missing evidence. |

The full rules, with the build, audit and handoff guidance, are in
section 8 of the manual.
