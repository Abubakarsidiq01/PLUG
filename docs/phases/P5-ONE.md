# P5 · Person One (MacBook) — Trust, safety, profile, notifications and admin

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P5`, you are in the wrong file.
> If `owner` is not `person_one`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P5 — Trust, safety, profile, notifications and admin |
| **Gate** | G5 |
| **Duration** | ~1.5 weeks |
| **You own** | backend, iOS, infrastructure, production |
| **Your directories** | `/backend, /ios, /infra, /db` |
| **You never** | nothing is off-limits, but /web, /tests, /fixtures and /design belong to Person Two — request changes there rather than making them |
| **Manual section** | §27.6 |
| **Other lane** | `docs/phases/P5-TWO.md` |

**Outcome this phase must reach**
A deliberately broken request is found and recovered through the audited admin path, with actor, reason, before and after recorded, and no direct database access at any point.

**Why it matters**
Everything built so far will eventually go wrong in production. This phase is what makes going wrong recoverable by a person who is not the engineer who wrote it.

You are the final technical authority on this phase. If something here conflicts with a decision Person Two made in the web lane, the contract decides — not seniority.

---

## 0. Before any code — the contract

This phase does not start with code. It starts with a fifteen-minute session
with the other person, which produces one merged pull request in `/contracts`
covering:

- RBAC roles and permissions
- Report, block and suspension schemas
- Audit event schema
- Notification preferences, deletion and retention rules
- Feature-flag read and write endpoints

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

- [ ] **P5.S1** — Freeze the RBAC, report, block, suspension, audit, notification, deletion and feature-flag contracts.
- [ ] **P5.S2** — Implement admin authorization server-side with least privilege. No client-only admin checks anywhere.
- [ ] **P5.S3** — Implement immutable audit events for every manual mutation and every security-sensitive action, per §19.10.
- [ ] **P5.S4** — Implement report, block, supplier suspension and restricted-query controls, with safe recovery operations.
- [ ] **P5.S5** — Implement notification preferences, APNs events, account deletion and de-identification, and retention rules.
- [ ] **P5.S6** — Build the iOS Profile and Settings, privacy, notifications, report and block, support, and destructive-confirmation screens.
- [ ] **P5.S7** — Configure secure HTTP headers and CORS for web endpoints, and production WAF rules as web exposure increases.
- [ ] **P5.S8** — Implement step-up authentication for high-risk admin actions.

---

## 3. When you work with the other person

1. The contract session for RBAC and audit schemas.
2. The design checkpoint for the full admin console — this is Person Two's largest surface.
3. The connected checkpoint, running the recovery scenario together.
4. The audit review, comparing the console's display against the stored events.

Outside these moments, work asynchronously. The fixtures in `/fixtures` are the
shared truth while the lanes are split — not a screenshot, not a message, not a
verbal description.

---

## 4. Tests that must pass

- [ ] Admin IDOR and RBAC tests across every admin resource.
- [ ] Every admin write requires a reason and produces an audit event.
- [ ] Blocked and suspended entities behave consistently across every surface.
- [ ] Account deletion revokes sessions and de-identifies data per the retention rule.
- [ ] Restricted and illegal-intent controls are active and audited.
- [ ] Step-up authentication is required for high-risk actions.
- [ ] Security headers verified from outside, on staging.

Verify with:

```bash
./gradlew :backend:test :backend:contractTest
./gradlew :backend:test --tests '*ArchitectureTest'
xcodebuild test -scheme PLUG-Staging -destination 'platform=iOS Simulator,name=iPhone 15'
# Then, on a REAL device, run this phase's primary flow before claiming it works.
```

---

## 5. Gate G5 — what the reviewer checks

- [ ] Admin IDOR and RBAC tests pass.
- [ ] Every admin write requires a reason and creates audit evidence.
- [ ] Blocked and suspended entities behave consistently.
- [ ] Delete-account behaviour is verified end to end.
- [ ] Restricted and illegal-intent controls are active.
- [ ] No direct database recovery procedure is used during normal operations.

---

## 6. Exit criteria — what is true when this phase is over

- [ ] A deliberately broken request is found and recovered entirely through the admin console.
- [ ] The audit trail shows actor, reason, before, after and timestamp for every action taken.
- [ ] A forbidden role is denied both in the interface and at the API.
- [ ] Account deletion is demonstrated and verified.
- [ ] `PROJECT_STATE.json` carries a signed `G5` entry.

---

## 7. Evidence to commit before the gate

Store everything under `evidence/P5/`:

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
4. Append the `G5` entry to `gate_log` in `PROJECT_STATE.json`, with both
   signatures, the evidence path and any known limitation.
5. Set `current_phase` to the next phase and rewrite `next_actions`.
6. Book the next phase's contract session before you close the laptop.

**Watch:** Admin experience can tempt unsafe shortcuts. A convenient bulk action with no reason field is how an audit trail becomes decorative.

---

## 9. If you are an AI assistant reading this file

Do not begin work from this file alone. Read `PROJECT_STATE.json` first, restate
the current phase, step, owner and top `next_actions` entry to the human, and
wait for confirmation. Work only on that one step. Never edit a path listed in
`do_not_touch`. Never add a field, endpoint, enum value or error code that is not
in `/contracts/openapi.yaml` — produce a contract pull request instead. End every
response with what you did not do, what is untested, and what you assumed.
The full rules are in §8 of the manual.
