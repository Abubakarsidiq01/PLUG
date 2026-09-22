# P3 · Person One (MacBook) — Supplier onboarding, SMS outreach, offers and reservation

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P3`, you are in the wrong file.
> If `owner` is not `person_one`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P3 — Supplier onboarding, SMS outreach, offers and reservation |
| **Gate** | G3 |
| **Duration** | ~2 weeks |
| **You own** | backend, iOS, infrastructure, production |
| **Your directories** | `/backend, /ios, /infra, /db` |
| **You never** | nothing is off-limits, but /web, /tests, /fixtures and /design belong to Person Two — request changes there rather than making them |
| **Manual section** | §27.4 |
| **Other lane** | `docs/phases/P3-TWO.md` |

**Outcome this phase must reach**
First real demo: an app request reaches an opted-in supplier by SMS, a real reply becomes one validated offer, and a selected offer becomes a reservation that only a supplier event can confirm.

**Why it matters**
This phase touches real people's phones. Every control here — consent, fan-out caps, STOP handling, signature verification, idempotency — exists because getting it wrong means texting a real business that never agreed to hear from you.

You are the final technical authority on this phase. If something here conflicts with a decision Person Two made in the web lane, the contract decides — not seniority.

---

## 0. Before any code — the contract

This phase does not start with code. It starts with a fifteen-minute session
with the other person, which produces one merged pull request in `/contracts`
covering:

- Supplier profile, consent, service-area and verification-status schemas
- Outbound message templates and the inbound command grammar
- `POST /v1/webhooks/twilio/inbound` and the status callback
- Offer schema, expiry, selection and reservation state transitions

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

- [ ] **P3.S1** — Freeze the supplier profile, consent, service-area, outbound message and inbound command contracts.
- [ ] **P3.S2** — Implement audited supplier onboarding state with explicit, recorded messaging consent.
- [ ] **P3.S3** — Integrate Twilio with signature validation, status callbacks, replay and idempotency protection, and opt-out suppression, per §19.8.
- [ ] **P3.S4** — Implement candidate matching with bounded fan-out: contact the best five or six first, and expand only by policy.
- [ ] **P3.S5** — Parse YES, NO, PAUSE, STOP and HELP deterministically. A malformed reply creates no offer and no supplier penalty.
- [ ] **P3.S6** — Create offer expiry, selection-race handling, reservation request, supplier confirmation and cancellation state machines.
- [ ] **P3.S7** — Implement the iOS Offer Detail, pending reservation, confirmed, timeout, expired and alternate-offer recovery states.
- [ ] **P3.S8** — Protect every endpoint with auth and rate limits; minimise supplier phone numbers and consumer identifiers in logs.
- [ ] **P3.S9** — Add the outbound worker with bounded concurrency, dead-letter handling and send-time suppression checks.

---

## 3. When you work with the other person

1. The contract session for supplier, message and offer schemas.
2. The design checkpoint for supplier SMS copy — this is Person Two's authored surface and it reaches real businesses.
3. The connected checkpoint, with a real opted-in test phone.
4. Supplier onboarding operations, throughout the phase.

Outside these moments, work asynchronously. The fixtures in `/fixtures` are the
shared truth while the lanes are split — not a screenshot, not a message, not a
verbal description.

---

## 4. Tests that must pass

- [ ] Twilio signature validation and replay tests.
- [ ] Duplicate webhook delivery produces exactly one transition and one offer.
- [ ] STOP and PAUSE suppress future outreach immediately, including for already-queued messages.
- [ ] Malformed reply creates no offer and applies no supplier penalty.
- [ ] Offer expiry and selection-race tests.
- [ ] Reservation never reaches Confirmed without a supplier event.
- [ ] Fan-out cap test: one request never contacts more suppliers than policy allows.
- [ ] Message and API log inspection: no secrets, no tokens, no unnecessary PII.

Verify with:

```bash
./gradlew :backend:test :backend:contractTest
./gradlew :backend:test --tests '*ArchitectureTest'
xcodebuild test -scheme PLUG-Staging -destination 'platform=iOS Simulator,name=iPhone 15'
# Then, on a REAL device, run this phase's primary flow before claiming it works.
```

---

## 5. Gate G3 — what the reviewer checks

- [ ] Twilio signature and replay tests pass.
- [ ] STOP and PAUSE suppress future outreach immediately.
- [ ] A duplicate webhook creates exactly one transition and one offer.
- [ ] Supplier fan-out caps prevent spam and cost explosion.
- [ ] A reservation never becomes Confirmed without a supplier event.
- [ ] Message and API logs expose no secrets, tokens or unnecessary PII.

---

## 6. Exit criteria — what is true when this phase is over

- [ ] A real opted-in phone receives the offer request and a real reply becomes one validated offer.
- [ ] A selected offer produces a reservation that reaches Confirmed only from a supplier event.
- [ ] A STOP reply immediately and verifiably ends outreach to that supplier.
- [ ] The admin messaging monitor shows the full trail with numbers masked.
- [ ] `PROJECT_STATE.json` carries a signed `G3` entry.

---

## 7. Evidence to commit before the gate

Store everything under `evidence/P3/`:

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
4. Append the `G3` entry to `gate_log` in `PROJECT_STATE.json`, with both
   signatures, the evidence path and any known limitation.
5. Set `current_phase` to the next phase and rewrite `next_actions`.
6. Book the next phase's contract session before you close the laptop.

**Watch:** SMS copy changes can break parsing. Copy and parser are one artefact: they change together, in one pull request, with the regression fixtures updated.

---

## 9. Contributor handoff

Read `PROJECT_STATE.json` and confirm the current phase, step, owner and next
accepted task before making changes. Coordinate changes to another engineer's
paths. Propose contract changes before adding fields, endpoints, enums or error
codes. Record verification, outstanding work and assumptions in the PR.
Follow [the contributor workflow](../CONTRIBUTOR_WORKFLOW.md).
