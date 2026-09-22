# P4 · Person Two (Windows) — NOW answers, Live Checks, Scout and credits

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P4`, you are in the wrong file.
> If `owner` is not `person_two`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P4 — NOW answers, Live Checks, Scout and credits |
| **Gate** | G4 |
| **Duration** | ~2 weeks |
| **You own** | public web, admin console, contracts, fixtures, QA, security testing |
| **Your directories** | `/web, /tests, /fixtures, /design` |
| **You never** | Xcode, SwiftUI builds, Keychain implementation, TestFlight, Apple signing, APNs certificates, production database access, or any change to /backend, /ios, /infra, /db |
| **Manual section** | §27.5 |
| **Other lane** | `docs/phases/P4-ONE.md` |

**Outcome this phase must reach**
One test phone requests a current condition; another answers it with one tap; the truth label is correct; and one answer produces at most one reward.

**Why it matters**
NOW is the feature most capable of becoming something it should not be. Every constraint here — structured answers, approved public places, hidden requester identity, notification caps — is what keeps a real-time utility from becoming a surveillance tool.

Everything in this file runs on Windows. If a task here appears to need a Mac, it has been written wrong — raise it rather than working around it.

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

- [ ] **P4.S1** — Build the NOW Monitor admin views: active live checks, observations, source, freshness, conflicts and expired evidence.
- [ ] **P4.S2** — Create fixtures for Confirmed, Recent, Estimated and Unknown for every V1 question type.
- [ ] **P4.S3** — Build Bruno tests for `GET /v1/now`, live-check creation and status, duplicate answers and reward idempotency.
- [ ] **P4.S4** — Run manual ground-truth comparison during beta rehearsals and document every mismatch.
- [ ] **P4.S5** — Review the Scout copy in Figma for privacy, structured answers, and the absence of any unrestricted surveillance prompt.
- [ ] **P4.S6** — Create the abuse test cases: private-person tracking, stalking-shaped questions, spam live checks and reward farming.

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
