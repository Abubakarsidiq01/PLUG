# P7 · Person Two (Windows) — One-zone beta launch

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P7`, you are in the wrong file.
> If `owner` is not `person_two`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P7 — One-zone beta launch |
| **Gate** | G7 |
| **Duration** | ongoing |
| **You own** | public web, admin console, contracts, fixtures, QA, security testing |
| **Your directories** | `/web, /tests, /fixtures, /design` |
| **You never** | Xcode, SwiftUI builds, Keychain implementation, TestFlight, Apple signing, APNs certificates, production database access, or any change to /backend, /ios, /infra, /db |
| **Manual section** | §27.8 |
| **Other lane** | `docs/phases/P7-ONE.md` |

**Outcome this phase must reach**
The daily smoke transaction passes, every incident has a runbook and an owner, no silent database edits occur, and expansion happens only on evidence.

**Why it matters**
A beta is an operating discipline, not a launch event. This phase is about what happens every day, and about resisting the pull to expand before the first zone actually works.

Everything in this file runs on Windows. If a task here appears to need a Mac, it has been written wrong — raise it rather than working around it.

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

- [ ] **P7.S1** — Own tester and supplier communication logs, qualitative feedback, bug reproduction and web and admin defects.
- [ ] **P7.S2** — Run the daily Playwright public-web smoke and the admin workflow smoke.
- [ ] **P7.S3** — Check broken links, support routes, legal pages, analytics and public status messaging after every web deployment.
- [ ] **P7.S4** — Review supplier response copy and customer confusion; create tickets with evidence rather than making silent fixes.
- [ ] **P7.S5** — Update the issue tracker with reproducible steps, severity, screenshots or log IDs, and the affected phase and contract.
- [ ] **P7.S6** — Join the daily and weekly go/no-go review. Person One remains the final technical release owner.

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
4. Append the `G7` entry to `gate_log` in `PROJECT_STATE.json`, with both
   signatures, the evidence path and any known limitation.
5. Set `current_phase` to the next phase and rewrite `next_actions`.
6. Book the next phase's contract session before you close the laptop.

**Watch:** The first quiet week will feel like permission to expand. It is not. Expansion before the verified fulfilment rate is stable turns one solvable problem into two unsolvable ones.

---

## 9. Contributor handoff

Read `PROJECT_STATE.json` and confirm the current phase, step, owner and next
accepted task before making changes. Coordinate changes to another engineer's
paths. Propose contract changes before adding fields, endpoints, enums or error
codes. Record verification, outstanding work and assumptions in the PR.
Follow [the contributor workflow](../CONTRIBUTOR_WORKFLOW.md).
