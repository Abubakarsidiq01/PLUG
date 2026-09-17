# P2 · Person Two (Windows) — Ask, parse, clarify, progress and seeded results

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P2`, you are in the wrong file.
> If `owner` is not `person_two`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P2 — Ask, parse, clarify, progress and seeded results |
| **Gate** | G2 |
| **Duration** | ~1.5 weeks |
| **You own** | public web, admin console, contracts, fixtures, QA, security testing |
| **Your directories** | `/web, /tests, /fixtures, /design` |
| **You never** | Xcode, SwiftUI builds, Keychain implementation, TestFlight, Apple signing, APNs certificates, production database access, or any change to /backend, /ios, /infra, /db |
| **Manual section** | §27.3 |
| **Other lane** | `docs/phases/P2-ONE.md` |

**Outcome this phase must reach**
“Barber under $35 in 30 minutes” produces validated structured results with honest progress, at most one clarifying question, and no fabricated values anywhere.

**Why it matters**
This is where the product becomes itself. It is also where the temptation to let the model decide things is strongest, and where a single fabricated price would undermine the entire premise.

Everything in this file runs on Windows. If a task here appears to need a Mac, it has been written wrong — raise it rather than working around it.

---

## 0. Before any code — the contract

This phase does not start with code. It starts with a fifteen-minute session
with the other person, which produces one merged pull request in `/contracts`
covering:

- `POST /v1/requests` and the full `Request` schema
- `POST /v1/requests/{id}/clarifications`
- `GET /v1/requests/{id}` and `GET /v1/requests/{id}/offers`
- The `status` and `next_action` enums
- The location object, money units and timestamp format

Nothing below this line begins until that pull request has merged with both
approvals. If you find yourself writing an endpoint that is not in the contract,
stop and open a contract pull request instead.

---

## 1. Environment

```powershell
docker compose up -d postgres redis
pnpm install
pnpm --filter @plug/web dev          # http://localhost:3000
bru run tests/api --env staging
pnpm --filter @plug/web test:e2e
```

If any of those commands fails on a clean machine, that is a bug in
`docs/onboarding/windows.md`, and fixing the
documentation is part of the work.

---

## 2. Your steps

Each line is one state token. Do them in order, update `PROJECT_STATE.json` as
you go, and open one pull request per step or per small group of related steps.

- [ ] **P2.S1** — Create and maintain the labelled intent and edge-case dataset, and the shared fixtures under `/fixtures`.
- [ ] **P2.S2** — Build the Bruno contract tests for request creation, clarification, polling and status, offers, cancellation, and every documented error.
- [ ] **P2.S3** — Review Figma for anti-vibecode compliance per §16: typography, spacing, no gradients, no glass, no pills, no fake proof, and every required state present.
- [ ] **P2.S4** — Build a web-based internal request inspector only if QA needs it; it must consume real staging data and must not duplicate canonical logic.
- [ ] **P2.S5** — Document the exact supported launch request grammar and the unsupported-category behaviour, for QA and support.
- [ ] **P2.S6** — Run the API abuse cases: overlong prompt, invalid coordinates, absurd budget, malformed timestamps, repeated submissions, and rate-limit behaviour.

---

## 3. When you work with the other person

1. The contract session for the Request schema — this is the most consequential contract in the product.
2. The design checkpoint for Ask, clarification, progress and results copy.
3. The connected checkpoint, to run the labelled dataset against real staging.

Outside these moments, work asynchronously. The fixtures in `/fixtures` are the
shared truth while the lanes are split — not a screenshot, not a message, not a
verbal description.

---

## 4. Tests that must pass

- [ ] Intent-extraction tests across the labelled dataset, including deliberately ambiguous input.
- [ ] State-machine legal-transition tests, including every illegal transition.
- [ ] Clarification logic tests: exactly one blocking question, never two.
- [ ] Contract tests for every documented response and error.
- [ ] Race and cancellation tests: cancelling mid-flight is safe and idempotent.
- [ ] Model-provider failure test: a timeout or invalid schema produces the deterministic fallback, not a 500.
- [ ] Restricted-intent test: a prohibited request creates no outreach and writes an audit event.

Verify with:

```powershell
pnpm --filter @plug/web typecheck
pnpm --filter @plug/web lint
pnpm --filter @plug/web test:unit
pnpm --filter @plug/web test:e2e
bru run tests/api --env staging
bru run tests/api/abuse --env staging
curl.exe -sI https://staging.plug.app | Sort-Object    # security headers
```

---

## 5. Gate G2 — what the reviewer checks

- [ ] Input schema rejects malformed and oversized values before business logic runs.
- [ ] AI and model output is schema-validated before persistence.
- [ ] No raw model reasoning is shown to users anywhere.
- [ ] Results use Confirmed, Recent, Estimated and Unknown correctly, set server-side.
- [ ] No horizontal overflow and no broken Dynamic Type state in iOS.
- [ ] Race and cancellation behaviour is safe and idempotent.

---

## 6. Exit criteria — what is true when this phase is over

- [ ] A supported request produces validated structured offers on a real device.
- [ ] Progress counts are real and visibly change as the server works.
- [ ] An unsupported category fails closed with a clear message.
- [ ] A provider failure degrades to the deterministic path without an error screen.
- [ ] `PROJECT_STATE.json` carries a signed `G2` entry.

---

## 7. Evidence to commit before the gate

Store everything under `evidence/P2/`:

- [ ] `web/` — one screenshot per required state from the matrix in §12,
      Playwright-captured at 360, 768 and 1280 px
- [ ] `failures/` — at least one deliberate failure, recovered, recorded
- [ ] `a11y/` — axe report with zero serious or critical issues
- [ ] `security/` — dependency scan, header check, forbidden-role test, abuse suite output
- [ ] The correlation ID from the connected checkpoint, quoted in the tracker

---

## 8. Closing the phase

1. Run the audit prompt from §8.4 of the manual against your surface.
2. Fix or formally except every critical and high finding. An exception needs an
   owner, a mitigation and an expiry date.
3. Run the connected checkpoint with the other person. Both of you, at the same
   time, against real staging.
4. Append the `G2` entry to `gate_log` in `PROJECT_STATE.json`, with both
   signatures, the evidence path and any known limitation.
5. Set `current_phase` to the next phase and rewrite `next_actions`.
6. Book the next phase's contract session before you close the laptop.

**Watch:** Person Two must not hardcode status strings in the web console. Consume the generated enum, so an added state breaks the build rather than rendering an empty screen.

---

## 9. If you are an AI assistant reading this file

Do not begin work from this file alone. Read `PROJECT_STATE.json` first, restate
the current phase, step, owner and top `next_actions` entry to the human, and
wait for confirmation. Work only on that one step. Never edit a path listed in
`do_not_touch`. Never add a field, endpoint, enum value or error code that is not
in `/contracts/openapi.yaml` — produce a contract pull request instead. End every
response with what you did not do, what is untested, and what you assumed.
The full rules are in §8 of the manual.
