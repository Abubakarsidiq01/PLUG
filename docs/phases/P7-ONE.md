# P7 · Person One (MacBook) — One-zone beta launch

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P7`, you are in the wrong file.
> If `owner` is not `person_one`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P7 — One-zone beta launch |
| **Gate** | G7 |
| **Duration** | ongoing |
| **You own** | backend, iOS, infrastructure, production |
| **Your directories** | `/backend, /ios, /infra, /db` |
| **You never** | nothing is off-limits, but /web, /tests, /fixtures and /design belong to Person Two — request changes there rather than making them |
| **Manual section** | §27.8 |
| **Other lane** | `docs/phases/P7-TWO.md` |

**Outcome this phase must reach**
The daily smoke transaction passes, every incident has a runbook and an owner, no silent database edits occur, and expansion happens only on evidence.

**Why it matters**
A beta is an operating discipline, not a launch event. This phase is about what happens every day, and about resisting the pull to expand before the first zone actually works.

You are the final technical authority on this phase. If something here conflicts with a decision Person Two made in the web lane, the contract decides — not seniority.

---

## 0. Before any code — the contract

This phase does not start with code. It starts with a fifteen-minute session
with the other person, which produces one merged pull request in `/contracts`
covering:

- No new contracts. Operational changes only, versioned as usual.

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

- [ ] **P7.S1** — Own production and staging backend, iOS TestFlight, messaging incidents, database, queue and integration failures, and security events.
- [ ] **P7.S2** — Monitor SLOs, rate limits, WAF and security events, database pool, queue depth, Twilio delivery and canonical state errors daily.
- [ ] **P7.S3** — Run the daily smoke transaction and a random completed-request audit.
- [ ] **P7.S4** — Perform manual recovery only through authorised, audited admin APIs or the console.
- [ ] **P7.S5** — Publish daily: verified fulfilment rate, supplier response rate, time to first verified offer, reservation completion and cost per fulfilment.
- [ ] **P7.S6** — Apply emergency feature flags or roll back when a safety or reliability threshold is breached, and document every incident.

---

## 3. When you work with the other person

1. Daily, briefly — the go/no-go review and the defect triage.
2. Weekly, longer — the metrics review and the expansion decision.

Outside these moments, work asynchronously. The fixtures in `/fixtures` are the
shared truth while the lanes are split — not a screenshot, not a message, not a
verbal description.

---

## 4. Tests that must pass

- [ ] Daily smoke transaction, end to end, on a real device.
- [ ] Daily web and admin Playwright smoke.
- [ ] Weekly random audit of completed requests against supplier reality.
- [ ] Weekly consent and STOP audit.

Verify with:

```bash
./gradlew :backend:test :backend:contractTest
./gradlew :backend:test --tests '*ArchitectureTest'
xcodebuild test -scheme PLUG-Staging -destination 'platform=iOS Simulator,name=iPhone 15'
# Then, on a REAL device, run this phase's primary flow before claiming it works.
```

---

## 5. Gate G7 — what the reviewer checks

- [ ] Consent and STOP audits pass.
- [ ] Every critical incident has a runbook and an owner.
- [ ] No silent direct database edits have occurred.
- [ ] Metrics and events are complete enough to make decisions from.
- [ ] Security alerts are reviewed rather than ignored.
- [ ] Expansion occurs only after stable evidence, not because the schedule says so.

---

## 6. Exit criteria — what is true when this phase is over

- [ ] Thirty consecutive days with the daily smoke passing and no unexplained canonical-state error.
- [ ] Verified fulfilment rate stable enough to make an expansion decision from.
- [ ] Every incident in the period has a written note and a closed action.
- [ ] `PROJECT_STATE.json` carries a signed `G7` entry and the expansion decision.

---

## 7. Evidence to commit before the gate

Store everything under `evidence/P7/`:

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
4. Append the `G7` entry to `gate_log` in `PROJECT_STATE.json`, with both
   signatures, the evidence path and any known limitation.
5. Set `current_phase` to the next phase and rewrite `next_actions`.
6. Book the next phase's contract session before you close the laptop.

**Watch:** The first quiet week will feel like permission to expand. It is not. Expansion before the verified fulfilment rate is stable turns one solvable problem into two unsolvable ones.

---

## 9. If you are an AI assistant reading this file

Do not begin work from this file alone. Read `PROJECT_STATE.json` first, restate
the current phase, step, owner and top `next_actions` entry to the human, and
wait for confirmation. Work only on that one step. Never edit a path listed in
`do_not_touch`. Never add a field, endpoint, enum value or error code that is not
in `/contracts/openapi.yaml` — produce a contract pull request instead. End every
response with what you did not do, what is untested, and what you assumed.
The full rules are in §8 of the manual.
