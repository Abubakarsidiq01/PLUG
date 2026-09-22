# P2 · Person One (MacBook) — Ask, parse, clarify, progress and seeded results

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P2`, you are in the wrong file.
> If `owner` is not `person_one`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P2 — Ask, parse, clarify, progress and seeded results |
| **Gate** | G2 |
| **Duration** | ~1.5 weeks |
| **You own** | backend, iOS, infrastructure, production |
| **Your directories** | `/backend, /ios, /infra, /db` |
| **You never** | nothing is off-limits, but /web, /tests, /fixtures and /design belong to Person Two — request changes there rather than making them |
| **Manual section** | §27.3 |
| **Other lane** | `docs/phases/P2-TWO.md` |

**Outcome this phase must reach**
“Barber under $35 in 30 minutes” produces validated structured results with honest progress, at most one clarifying question, and no fabricated values anywhere.

**Why it matters**
This is where the product becomes itself. It is also where the temptation to let the model decide things is strongest, and where a single fabricated price would undermine the entire premise.

You are the final technical authority on this phase. If something here conflicts with a decision Person Two made in the web lane, the contract decides — not seniority.

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

```bash
docker compose up -d postgres redis
./gradlew :backend:flywayMigrate
./gradlew :backend:bootRun          # http://localhost:8080
open ios/PLUG.xcodeproj             # scheme: PLUG-Staging
```

If any of those commands fails on a clean machine, that is a bug in
`docs/onboarding/mac.md`, and fixing the
documentation is part of the work.

---

## 2. Your steps

Each line is one state token. Do them in order, update `PROJECT_STATE.json` as
you go, and open one pull request per step or per small group of related steps.

- [ ] **P2.S1** — Freeze the Request, constraints, status, next_action, location, money and timestamp contracts.
- [ ] **P2.S2** — Implement the intent adapter with strict structured output and deterministic validation, per §19.5. Treat model output as untrusted.
- [ ] **P2.S3** — Create the request state machine with legal-transition tests and idempotent cancellation, per §19.6.
- [ ] **P2.S4** — Create the `requests`, `request_constraints`, `places` and supplier-seed migrations with the required indexes.
- [ ] **P2.S5** — Implement the clarification decision: ask only when a missing field genuinely blocks execution, and never more than one question.
- [ ] **P2.S6** — Expose real progress counts and `next_action`. No client-side timers pretending to be progress.
- [ ] **P2.S7** — Return only structured, validated seeded offers. The app never fabricates price, availability, wait or confirmation.
- [ ] **P2.S8** — Add request-creation rate limits, request-size limits and restricted-intent policy enforcement.
- [ ] **P2.S9** — Build the SwiftUI Ask, clarification, progress, results and offer-detail screens from Figma, including the offline, no-match, parser-error and cached states.

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

```bash
./gradlew :backend:test :backend:contractTest
./gradlew :backend:test --tests '*ArchitectureTest'
xcodebuild test -scheme PLUG-Staging -destination 'platform=iOS Simulator,name=iPhone 15'
# Then, on a REAL device, run this phase's primary flow before claiming it works.
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

- [ ] `ios/` — one screenshot per required state from the matrix in §12,
      on a real device, at default and largest Dynamic Type
- [ ] `failures/` — at least one deliberate failure, recovered, recorded
- [ ] `a11y/` — VoiceOver walkthrough of the primary flow
- [ ] `logs/` — the request ID from the connected checkpoint, in the backend log
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

## 9. Contributor handoff

Read `PROJECT_STATE.json` and confirm the current phase, step, owner and next
accepted task before making changes. Coordinate changes to another engineer's
paths. Propose contract changes before adding fields, endpoints, enums or error
codes. Record verification, outstanding work and assumptions in the PR.
Follow [the contributor workflow](../CONTRIBUTOR_WORKFLOW.md).
