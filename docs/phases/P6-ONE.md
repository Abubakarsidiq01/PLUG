# P6 · Person One (MacBook) — Beta hardening and release readiness

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P6`, you are in the wrong file.
> If `owner` is not `person_one`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P6 — Beta hardening and release readiness |
| **Gate** | G6 |
| **Duration** | ~1.5 weeks |
| **You own** | backend, iOS, infrastructure, production |
| **Your directories** | `/backend, /ios, /infra, /db` |
| **You never** | nothing is off-limits, but /web, /tests, /fixtures and /design belong to Person Two — request changes there rather than making them |
| **Manual section** | §27.7 |
| **Other lane** | `docs/phases/P6-TWO.md` |

**Outcome this phase must reach**
Backup restore proven, rollback rehearsed, load and dependency-failure drills passed, the full security and accessibility sweep clean, and zero open critical or high findings without a dated exception.

**Why it matters**
This is the phase that decides whether the beta is a product or a demonstration. Everything here is a drill, and a drill that has not been run has not passed.

You are the final technical authority on this phase. If something here conflicts with a decision Person Two made in the web lane, the contract decides — not seniority.

---

## 0. Before any code — the contract

This phase does not start with code. It starts with a fifteen-minute session
with the other person, which produces one merged pull request in `/contracts`
covering:

- No new contracts. Only versioned corrections found during hardening.

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

- [ ] **P6.S1** — Complete the idempotency review for every externally visible mutation, webhook, credit and booking.
- [ ] **P6.S2** — Run backend load, webhook burst, database saturation, queue backlog, timeout and dependency-failure tests.
- [ ] **P6.S3** — Tune the database pool, indexes, query timeouts, HTTP client timeouts, retry, backoff, jitter and circuit breakers from measured results.
- [ ] **P6.S4** — Enable and verify WAF, private data-tier networking, KMS encryption, Secrets Manager and least-privilege IAM.
- [ ] **P6.S5** — Run the backup restore drill and record the actual RPO and RTO achieved.
- [ ] **P6.S6** — Create dashboards and alerts for the four golden signals plus database pool, queue depth, Twilio failures, auth failures and rate-limit events.
- [ ] **P6.S7** — Prepare the TestFlight build, App Store privacy disclosures, iOS accessibility checks and permission-denial behaviour.
- [ ] **P6.S8** — Define the deployment and rollback strategy and rehearse the rollback in staging. Do not claim zero downtime until it is proven.

---

## 3. When you work with the other person

1. Throughout — this phase is closer to equal effort than any other.
2. The failure-matrix review, jointly, running every drill in §29.
3. The release gate itself.

Outside these moments, work asynchronously. The fixtures in `/fixtures` are the
shared truth while the lanes are split — not a screenshot, not a message, not a
verbal description.

---

## 4. Tests that must pass

- [ ] Load test at expected beta traffic and at three times expected traffic.
- [ ] Webhook burst test.
- [ ] Database saturation and slow-query test.
- [ ] Queue backlog and poison-message test.
- [ ] Dependency failure and circuit-breaker test for Twilio, the model provider and Places.
- [ ] Backup restore drill with measured RPO and RTO.
- [ ] Rollback rehearsal with a real deployment.
- [ ] Full accessibility sweep on both surfaces.
- [ ] Full external security scan.

Verify with:

```bash
./gradlew :backend:test :backend:contractTest
./gradlew :backend:test --tests '*ArchitectureTest'
xcodebuild test -scheme PLUG-Staging -destination 'platform=iOS Simulator,name=iPhone 15'
# Then, on a REAL device, run this phase's primary flow before claiming it works.
```

---

## 5. Gate G6 — what the reviewer checks

- [ ] Any unresolved critical or high security finding without an approved, dated mitigation blocks release.
- [ ] Any false booking, false Confirmed or false NOW truth state blocks release.
- [ ] Backup restore not proven blocks release.
- [ ] Any critical auth, IDOR or rate-limit failure blocks release.
- [ ] A production secret exposed to the frontend, the repository or a log blocks release.
- [ ] A core user journey crash or unrecoverable error blocks release.
- [ ] A broken legal or privacy path blocks release.
- [ ] Material mobile overflow or an inaccessible primary action on web blocks release.
- [ ] No rollback path for the release candidate blocks release.

---

## 6. Exit criteria — what is true when this phase is over

- [ ] Every drill in §29 has been run and recorded.
- [ ] Restore and rollback are proven, with measured numbers.
- [ ] Both surfaces pass accessibility and security sweeps.
- [ ] The TestFlight build is ready with accurate privacy disclosures.
- [ ] `PROJECT_STATE.json` carries a signed `G6` entry.

---

## 7. Evidence to commit before the gate

Store everything under `evidence/P6/`:

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
4. Append the `G6` entry to `gate_log` in `PROJECT_STATE.json`, with both
   signatures, the evidence path and any known limitation.
5. Set `current_phase` to the next phase and rewrite `next_actions`.
6. Book the next phase's contract session before you close the laptop.

**Watch:** The temptation at this gate is to accept a finding “for now” without a date. An exception without an expiry is not an exception; it is a decision to ship the problem permanently.

---

## 9. Contributor handoff

Read `PROJECT_STATE.json` and confirm the current phase, step, owner and next
accepted task before making changes. Coordinate changes to another engineer's
paths. Propose contract changes before adding fields, endpoints, enums or error
codes. Record verification, outstanding work and assumptions in the PR.
Follow [the contributor workflow](../CONTRIBUTOR_WORKFLOW.md).
