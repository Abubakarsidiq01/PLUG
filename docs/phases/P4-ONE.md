# P4 · Person One (MacBook) — NOW answers, Live Checks, Scout and credits

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P4`, you are in the wrong file.
> If `owner` is not `person_one`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P4 — NOW answers, Live Checks, Scout and credits |
| **Gate** | G4 |
| **Duration** | ~2 weeks |
| **You own** | backend, iOS, infrastructure, production |
| **Your directories** | `/backend, /ios, /infra, /db` |
| **You never** | nothing is off-limits, but /web, /tests, /fixtures and /design belong to Person Two — request changes there rather than making them |
| **Manual section** | §27.5 |
| **Other lane** | `docs/phases/P4-TWO.md` |

**Outcome this phase must reach**
One test phone requests a current condition; another answers it with one tap; the truth label is correct; and one answer produces at most one reward.

**Why it matters**
NOW is the feature most capable of becoming something it should not be. Every constraint here — structured answers, approved public places, hidden requester identity, notification caps — is what keeps a real-time utility from becoming a surveillance tool.

You are the final technical authority on this phase. If something here conflicts with a decision Person Two made in the web lane, the contract decides — not seniority.

---

## 0. Before any code — the contract

This phase does not start with code. It starts with a fifteen-minute session
with the other person, which produces one merged pull request in `/contracts`
covering:

- Observation and evidence schema, place identifiers
- Live Check states, structured answer options, freshness windows
- Scout eligibility, notification payload, credit rules
- `GET /v1/now` and the Live Check creation and status endpoints

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

- [ ] **P4.S1** — Freeze the observation and evidence schema, place IDs, Live Check states, structured answer options, freshness windows and credit rules.
- [ ] **P4.S2** — Implement the observation source hierarchy and deterministic truth labels. Expired evidence cannot remain Confirmed.
- [ ] **P4.S3** — Implement the eligible-scout query with privacy protection and notification caps.
- [ ] **P4.S4** — Implement an append-only, idempotent credit ledger with anti-reward-farming checks.
- [ ] **P4.S5** — Implement the iOS NOW Answer, Unknown fallback, Scout opt-in, task list and structured one-tap answer screens.
- [ ] **P4.S6** — Integrate APNs and deep links for eligible tasks. Never expose requester identity to a scout.
- [ ] **P4.S7** — Add rate limits and abuse controls for creating live checks and for answering tasks.
- [ ] **P4.S8** — Implement conflict resolution: conflicting answers either resolve by rule or remain non-confirmed.

---

## 3. When you work with the other person

1. The contract session for observation, freshness and credit rules.
2. The design checkpoint for Scout copy and the structured answer options — the privacy boundary lives in this copy.
3. The connected checkpoint, a two-phone Live Check.
4. The abuse review, which is Person Two's to lead.

Outside these moments, work asynchronously. The fixtures in `/fixtures` are the
shared truth while the lanes are split — not a screenshot, not a message, not a
verbal description.

---

## 4. Tests that must pass

- [ ] Truth-label tests for every source and freshness combination.
- [ ] Expiry test: a Confirmed observation becomes Unknown, not Estimated, when its window closes.
- [ ] Conflict test: two contradicting answers resolve by rule or remain non-confirmed.
- [ ] Duplicate answer and retry: exactly one reward is created.
- [ ] Scout privacy test: the requester's identity is not present in any scout-facing payload.
- [ ] Notification cap test: a scout cannot be flooded.
- [ ] Abuse test: a private-person tracking question is refused and audited.

Verify with:

```bash
./gradlew :backend:test :backend:contractTest
./gradlew :backend:test --tests '*ArchitectureTest'
xcodebuild test -scheme PLUG-Staging -destination 'platform=iOS Simulator,name=iPhone 15'
# Then, on a REAL device, run this phase's primary flow before claiming it works.
```

---

## 5. Gate G4 — what the reviewer checks

- [ ] Unknown never becomes Confirmed without valid evidence.
- [ ] A requester cannot identify a scout, and a scout cannot identify a requester.
- [ ] No unrestricted free-text surveillance task can be created.
- [ ] Location data is minimised and its retention is defined.
- [ ] One answer produces at most one reward.
- [ ] Conflicting evidence either resolves by rule or remains non-confirmed.

---

## 6. Exit criteria — what is true when this phase is over

- [ ] A two-phone Live Check succeeds end to end on real devices.
- [ ] Truth labels are correct across all four states, verified against ground truth.
- [ ] The NOW Monitor shows sources, freshness and conflicts accurately.
- [ ] The abuse suite passes with every prohibited question refused and audited.
- [ ] `PROJECT_STATE.json` carries a signed `G4` entry.

---

## 7. Evidence to commit before the gate

Store everything under `evidence/P4/`:

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
4. Append the `G4` entry to `gate_log` in `PROJECT_STATE.json`, with both
   signatures, the evidence path and any known limitation.
5. Set `current_phase` to the next phase and rewrite `next_actions`.
6. Book the next phase's contract session before you close the laptop.

**Watch:** Person Two cannot change answer options unilaterally — the options are the schema. A new option is a contract change, a migration and a fixture update.

---

## 9. Contributor handoff

Read `PROJECT_STATE.json` and confirm the current phase, step, owner and next
accepted task before making changes. Coordinate changes to another engineer's
paths. Propose contract changes before adding fields, endpoints, enums or error
codes. Record verification, outstanding work and assumptions in the PR.
Follow [the contributor workflow](../CONTRIBUTOR_WORKFLOW.md).
