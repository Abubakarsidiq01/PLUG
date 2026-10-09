# P3 · Person Two (Windows) — Provider inbox, offers, SMS channel and trust score v1

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P3`, you are in the wrong file.
> If `owner` is not `person_two`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P3 — Provider inbox, offers, SMS channel and trust score v1 |
| **Gate** | G3 |
| **Duration** | ~2 weeks |
| **You own** | public web, admin console, contracts, fixtures, QA, security testing |
| **Your directories** | `/web, /tests, /fixtures, /design` |
| **You never** | Xcode, SwiftUI builds, Keychain implementation, TestFlight, Apple signing, APNs certificates, production database access, or any change to /backend, /ios, /infra, /db |
| **Manual section** | §27.4 |
| **Other lane** | `docs/phases/P3-ONE.md` |

**Outcome this phase must reach**
A matched provider receives the request in their own inbox, sends a real offer with a price and a time, and the asker chooses between real offers that carry a score. On the SMS side: an app request reaches an opted-in supplier by text, a real reply becomes one validated offer, and a selected offer becomes a reservation that only a supplier event can confirm.

> **Updated to manual v4 §27.4 on 2026-10-09.** Phase 3 now carries two channels: SMS for
> businesses that prefer text, and the in-app inbox for individual providers, who are the
> point of the product. Both produce the same validated Offer, under one combined fan-out
> ceiling, and providers get trust score v1. The contract is
> [0.7.0](../../contracts/CHANGELOG.md), proposed in P3.S1.

**Why it matters**
Phase 3 was already the supplier phase. It now carries two channels instead of one. It also touches real people's phones. Every control here — consent, fan-out caps, STOP handling, signature verification, idempotency — exists because getting it wrong means texting a real business that never agreed to hear from you.

Everything in this file runs on Windows. If a task here appears to need a Mac, it has been written wrong — raise it rather than working around it.

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

```powershell
pnpm install --frozen-lockfile
pnpm test:contracts                  # contract, fixtures, SMS copy and grammar
pnpm --filter @plug/web dev          # http://localhost:3000
pnpm --filter @plug/web test:e2e
```

For the database, backend and Bruno CLI, follow [Windows onboarding](../onboarding/windows.md).
There is no standing staging URL; use the current checkpoint tunnel as described in
`tests/api/environments/README.md`.

**Your P3.S1 starting point:** `contracts/messages/` holds Person One's draft of every SMS
and the push alert, the reply grammar and 76 regression cases. The wording is yours: rewrite
it, and `pnpm test:contracts` tells you whether it still fits two segments, stays in GSM-7 and
asks only for words the grammar reads.

If any of those commands fails on a clean machine, that is a bug in
`docs/onboarding/windows.md`, and fixing the
documentation is part of the work.

---

## 2. Your steps

Each line is one state token. Do them in order, update `PROJECT_STATE.json` as
you go, and open one pull request per step or per small group of related steps.

- [ ] **P3.S1** — Own the supplier SMS wording, the HELP text and the STOP and PAUSE clarity, versioned under `/contracts/messages` with regression fixtures.
- [ ] **P3.S2** — Build the supplier onboarding and admin web UI against Person One's APIs: business name, services, hours, radius, contact, consent and verification status.
- [ ] **P3.S3** — Build the supplier dashboard and offer-response web UI if it is enabled this release; otherwise keep it behind a flag with no fake functionality.
- [ ] **P3.S4** — Run real browser and Bruno tests for onboarding, consent, pause, stop, malformed replies, duplicate replies and offer expiry.
- [ ] **P3.S5** — Run Playwright on the supplier and admin routes for validation, mobile responsiveness, error states and authorization boundaries.
- [ ] **P3.S6** — Assist with supplier onboarding operations and record every real consent path. Never edit the database directly.
- [ ] **P3.S7** — Build the messaging monitor admin view: delivery status, inbound parse results, the opt-out list and duplicate suppression.
- [ ] **P3.S8** — Own the provider-facing copy end to end: the notification text, the inbox empty state, the offer composer, the decline confirmation and the expiry notice.
- [ ] **P3.S9** — Build the admin provider-management screens: profiles, skills, radius, verification status, suspension, and the match history for any request.
- [ ] **P3.S10** — Write Playwright coverage for the provider web surfaces, including the forbidden-role and unauthenticated cases.
- [ ] **P3.S11** — Write the Bruno cases for offers: valid offer, offer above the asker's budget, offer after expiry, duplicate offer from the same provider, and offer from a provider who was never matched.
- [ ] **P3.S12** — Test notification caps from outside: trigger many simultaneous matches for one provider and prove the cap holds.

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
