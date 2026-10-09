# P3 · Person One (MacBook) — Provider inbox, offers, SMS channel and trust score v1

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P3`, you are in the wrong file.
> If `owner` is not `person_one`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P3 — Provider inbox, offers, SMS channel and trust score v1 |
| **Gate** | G3 |
| **Duration** | ~2 weeks |
| **You own** | backend, iOS, infrastructure, production |
| **Your directories** | `/backend, /ios, /infra, /db` |
| **You never** | nothing is off-limits, but /web, /tests, /fixtures and /design belong to Person Two — request changes there rather than making them |
| **Manual section** | §27.4 |
| **Other lane** | `docs/phases/P3-TWO.md` |

**Outcome this phase must reach**
A matched provider receives the request in their own inbox, sends a real offer with a price and a time, and the asker chooses between real offers that carry a score. On the SMS side: an app request reaches an opted-in supplier by text, a real reply becomes one validated offer, and a selected offer becomes a reservation that only a supplier event can confirm.

> **Updated to manual v4 §27.4 on 2026-10-09.** Phase 3 now carries two channels: SMS for
> businesses that prefer text, and the in-app inbox for individual providers, who are the
> point of the product. Both produce the same validated Offer, under one combined fan-out
> ceiling, and providers get trust score v1. The contract is
> [0.7.0](../../contracts/CHANGELOG.md), proposed in P3.S1.

**Why it matters**
Phase 3 was already the supplier phase. It now carries two channels instead of one. It also touches real people's phones. Every control here — consent, fan-out caps, STOP handling, signature verification, idempotency — exists because getting it wrong means texting a real business that never agreed to hear from you.

You are the final technical authority on this phase. If something here conflicts with a decision Person Two made in the web lane, the contract decides — not seniority.

---

## Carried in from Phase 1

- **Phone code delivery is this phase's job (ADR-007).** Phase 1 built the whole
  verification mechanism — challenge, expiry, attempt limit, three layered rate
  limits, constant-time comparison, audit events — behind the `PhoneCodeSender`
  interface, with no implementation. Implement it with Twilio and change
  `plug.identity.phone-delivery`. Nothing above the interface has to move. Until
  that lands, `POST /v1/auth/phone/start` answers `503 dependency_unavailable`,
  and no code is ever written to the application log in any environment.
- **Move the rate limits to Redis before running more than one instance.**
  `FixedWindowLimiter` counts in one process's memory. That is correct for a
  single instance and silently wrong for two, and this phase adds supplier
  fan-out and inbound webhooks. The root `docker-compose.yml` already provisions a Redis
  nobody uses yet.
- **Extend the BOLA test to supplier resource ids.** manual.docx §27.2 asks for
  user, supplier and admin. `SessionLifecycleTest` covers user and admin;
  supplier resources do not exist until this phase, so the third class is
  genuinely uncovered until you add it here.
- **Give `PLUG_IDENTITY_PEPPER` a real home.** It currently lives only in
  `.env.local` and the CI workflow. ADR-004 says AWS is revisited no later than
  this phase, because Twilio needs a stable webhook URL; move the pepper into
  Secrets Manager at the same time. Rotating it makes every stored phone hash,
  Apple subject and code hash unrecognisable — treat it as permanent.
- **Webhook authentication is not session authentication.** Twilio requests
  carry a signature, not a bearer token. Verify the signature in the handler and
  keep `/v1/webhooks/**` off the session filter's rules.

## Carried in from Phase 2

- **Fan-out is already capped at 6 then a combined 16** (`MatchService`, as built in Phase 2).
  Phase 3 adds the 4 + 4 expansion steps and makes SMS suppliers and in-app providers share
  that one ceiling. The manual's two sketches say 14 and 16; 0.7.0 proposes 16.
- **`request_matches` already records who was notified.** Extend it for channel, wave and
  outcome rather than adding a second table; `GET /v1/admin/requests/{id}/matches` reads it.
- **Seed offers stay `estimated` at best.** Real `sms` and `portal` offers are `confirmed`
  when made and age from `observed_at`.
- **The iOS `Offer` model already accepts 0.7.0** (optional `place`, `distance_m`, `note`,
  `not_confirmed`), changed with the contract pull request. The app does not yet poll while
  `await_supplier_confirmation` or show the reservation; that is P3.S7.

---

## 0. Before any code — the contract

This phase does not start with code. It starts with a fifteen-minute session
with the other person, which produces one merged pull request in `/contracts`
covering:

- Supplier profile, consent, service-area and verification-status schemas
- Outbound message templates and the inbound command grammar
- `POST /v1/webhooks/twilio/inbound` and the status callback
- Offer schema, expiry, selection and reservation state transitions
- `POST /v1/requests/{id}/offers` — in-app provider offers
- Provider notification payload and per-hour cap
- Offer schema shared by the SMS and in-app paths
- Trust-score v1 fields on the provider resource

Nothing below this line begins until that pull request has merged with both
approvals. If you find yourself writing an endpoint that is not in the contract,
stop and open a contract pull request instead.

---

## 1. Environment

```bash
docker compose up -d postgres redis
sh tools/run-phase2-local.sh        # loopback port 18080; migrations run at startup
open ios/Plug.xcodeproj             # scheme: Plug
```

Twilio needs a webhook URL that does not change between sessions (ADR-004 says AWS is
revisited no later than this phase). Until one exists, inbound SMS can only be exercised
with signed test requests, and no real text is sent.

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
- [ ] **P3.S10** — Implement the provider inbox: matched requests delivered in-app with their own notification sound and category, capped per provider per hour.
- [ ] **P3.S11** — Implement `POST /v1/requests/{id}/offers` for in-app provider offers, alongside the existing SMS path. Both produce the same validated Offer.
- [ ] **P3.S12** — Implement decline-versus-silence tracking. A decline is a reply and costs the provider nothing; silence is what lowers a response score.
- [ ] **P3.S13** — Implement the first version of the trust score: completion, reliability, responsiveness and standing. Customer rating lands in Phase 5 with reviews.
- [ ] **P3.S14** — Add the new_provider state. A provider with fewer than three completed jobs shows New, never a score of zero.
- [ ] **P3.S15** — Implement per-request fan-out caps for in-app matching that mirror the SMS caps, and a combined ceiling across both channels.
- [ ] **P3.S16** — Build the SwiftUI provider inbox, offer composer and offer-sent states from Figure A2.

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
- [ ] The P3.S5 parser passes every case in `contracts/messages/cases.v1.json`.
- [ ] Notification cap: many simultaneous matches for one provider produce at most the hourly cap of alerts.
- [ ] Supplier, provider and admin resource ids: another caller's id is 404 (the third BOLA class from §27.2).

Verify with:

```bash
pnpm test:contracts                       # contract, fixtures, SMS copy and grammar
./backend/dev check contractTest
./backend/dev databaseTest                # isolated database, see docs/runbooks/phase2-local.md
xcodebuild test -project ios/Plug.xcodeproj -scheme Plug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
# Then, on a REAL device and a real opted-in phone, run this phase's primary flow before claiming it works.
```

---

## 5. Gate G3 — what the reviewer checks

- [ ] Twilio signature and replay tests pass.
- [ ] STOP and PAUSE suppress future outreach immediately.
- [ ] A duplicate webhook creates exactly one transition and one offer.
- [ ] Supplier fan-out caps prevent spam and cost explosion.
- [ ] A reservation never becomes Confirmed without a supplier event.
- [ ] Message and API logs expose no secrets, tokens or unnecessary PII.
- [ ] A provider receives a matched request in the inbox with its own notification sound, inside the per-hour cap.
- [ ] An in-app offer and an SMS offer produce an identical validated Offer.
- [ ] Declining is recorded as a reply and does not lower the response score; silence does.
- [ ] A provider with fewer than three completed jobs shows New, never a zero.

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
