# P5 · Person Two (Windows) — Trust, safety, profile, notifications and admin

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P5`, you are in the wrong file.
> If `owner` is not `person_two`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P5 — Trust, safety, profile, notifications and admin |
| **Gate** | G5 |
| **Duration** | ~1.5 weeks |
| **You own** | public web, admin console, contracts, fixtures, QA, security testing |
| **Your directories** | `/web, /tests, /fixtures, /design` |
| **You never** | Xcode, SwiftUI builds, Keychain implementation, TestFlight, Apple signing, APNs certificates, production database access, or any change to /backend, /ios, /infra, /db |
| **Manual section** | §27.6 |
| **Other lane** | `docs/phases/P5-ONE.md` |

**Outcome this phase must reach**
A deliberately broken request is found and recovered through the audited admin path, with actor, reason, before and after recorded, and no direct database access at any point.

**Why it matters**
Everything built so far will eventually go wrong in production. This phase is what makes going wrong recoverable by a person who is not the engineer who wrote it.

Everything in this file runs on Windows. If a task here appears to need a Mac, it has been written wrong — raise it rather than working around it.

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

- [ ] **P5.S1** — Own the admin web experience for the Live Request Inspector, Business Management, NOW Monitor, Messaging Monitor, Reports and Moderation, and feature flags.
- [ ] **P5.S2** — Implement web error boundaries, loading, empty and error states, responsive behaviour and accessible form controls throughout.
- [ ] **P5.S3** — Write Playwright tests for admin login, forbidden role, the report flow, suspension, the recovery-reason requirement, deep links and destructive confirmation.
- [ ] **P5.S4** — Implement the public support, privacy and terms pages, and ensure navigation and footer links are complete.
- [ ] **P5.S5** — Run broken-link, axe accessibility, responsive overflow and security-header checks against staging.
- [ ] **P5.S6** — Audit records jointly with Person One: every mutation shows actor, reason, before, after and timestamp.

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
