# P1 · Person Two (Windows) — Identity and consent

**Joining after automated Phase 0 verification:** begin with the
[personal setup and evidence handoff](../onboarding/person-two-phase1-handoff.md).
Your interactive Windows/Docker/WSL setup was deferred to this first session
by Person One under ADR-005; hosted CI did not perform it on your computer.

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P1`, you are in the wrong file.
> If `owner` is not `person_two`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P1 — Identity and consent |
| **Gate** | G1 |
| **Duration** | ~1 week |
| **You own** | public web, admin console, contracts, fixtures, QA, security testing |
| **Your directories** | `/web, /tests, /fixtures, /design` |
| **You never** | Xcode, SwiftUI builds, Keychain implementation, TestFlight, Apple signing, APNs certificates, production database access, or any change to /backend, /ios, /infra, /db |
| **Manual section** | §27.2 |
| **Other lane** | `docs/phases/P1-ONE.md` |

**Outcome this phase must reach**
A real user signs in with Apple on a real device, the session survives a relaunch, logout revokes the session server-side, and no token appears in any log.

**Why it matters**
Identity is the first thing that carries real consequences. Every later authorization check, every audit event and every consent record depends on there being exactly one identity model, established now and not invented a second time in Phase 3.

Everything in this file runs on Windows. If a task here appears to need a Mac, it has been written wrong — raise it rather than working around it.

---

## 0. Before any code — the contract

This phase does not start with code. It starts with a fifteen-minute session
with the other person, which produces one merged pull request in `/contracts`
covering:

- `POST /v1/auth/apple`
- `POST /v1/auth/phone/start` and `POST /v1/auth/phone/verify`
- `POST /v1/auth/guest`
- The Authorization header, access and refresh rules, and the standard auth error codes
- Consent version and the account-upgrade behaviour

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

- [ ] **P1.S1** — Build the public Privacy Policy, Terms and Support route shells in `/web`, using the final legal content once it is approved.
- [ ] **P1.S2** — Build the admin login and protected-route shell against the approved backend session design. No frontend-only authorization.
- [ ] **P1.S3** — Create the Bruno auth collection covering valid, expired, replayed and invalid tokens, wrong code, brute force and rate limiting, and guest cases.
- [ ] **P1.S4** — Create Playwright tests proving protected admin routes cannot be reached when unauthenticated, and that the API is never called with an unauthenticated session.
- [ ] **P1.S5** — Review the consent copy, the error copy and the account-upgrade experience in Figma and in the browser.
- [ ] **P1.S6** — Run a dependency and security scan, and verify no secret or configuration value leaks into the rendered HTML or JavaScript.
- [ ] **P1.S7** — Verify the security headers on staging from outside, with `curl -sI`, and attach the output as evidence.

---

## 3. When you work with the other person

1. The auth contract session — token payload, refresh rules and every error code.
2. The design checkpoint for consent copy, error copy and the upgrade banner.
3. The connected checkpoint, to run the auth abuse suite against real staging.

Outside these moments, work asynchronously. The fixtures in `/fixtures` are the
shared truth while the lanes are split — not a screenshot, not a message, not a
verbal description.

---

## 4. Tests that must pass

- [ ] Replayed and expired Apple token tests.
- [ ] Phone brute-force and rate-limit tests.
- [ ] Keychain persistence and logout tests.
- [ ] Guest restriction and upgrade tests.
- [ ] IDOR and auth-bypass tests on a protected endpoint.
- [ ] Refresh-token rotation and replay test: a reused rotated token is rejected and the affected chain is revoked.
- [ ] BOLA test across user, supplier and admin resource IDs.
- [ ] Log inspection confirms no access token, refresh token, OTP secret or authorization header is emitted.

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

## 5. Gate G1 — what the reviewer checks

- [ ] Brute-force controls verified against real staging.
- [ ] BOLA and IDOR auth-bypass tests pass.
- [ ] Session logout and revocation behaviour verified server-side, not just in the client.
- [ ] No token appears in any log, analytics event or crash breadcrumb.
- [ ] Admin protected routes enforce server-side authorization.
- [ ] Consent version is persisted and visible in admin or audit data.

---

## 6. Exit criteria — what is true when this phase is over

- [ ] The Apple path persists across a relaunch on a real device.
- [ ] The guest path is clearly limited, and the limits are tested.
- [ ] Logout revokes or invalidates the session server-side.
- [ ] Consent version is stored and auditable.
- [ ] `PROJECT_STATE.json` carries a signed `G1` entry.

---

## 7. Evidence to commit before the gate

Store everything under `evidence/P1/`:

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
4. Append the `G1` entry to `gate_log` in `PROJECT_STATE.json`, with both
   signatures, the evidence path and any known limitation.
5. Set `current_phase` to the next phase and rewrite `next_actions`.
6. Book the next phase's contract session before you close the laptop.

**Watch:** Changes to token expiry or refresh behaviour after this phase ripple through every screen that can be open when a session ends. Decide the lifetimes now and write them into the contract.

---

## 9. If you are an AI assistant reading this file

Do not begin work from this file alone. Read `PROJECT_STATE.json` first, restate
the current phase, step, owner and top `next_actions` entry to the human, and
wait for confirmation. Work only on that one step. Never edit a path listed in
`do_not_touch`. Never add a field, endpoint, enum value or error code that is not
in `/contracts/openapi.yaml` — produce a contract pull request instead. End every
response with what you did not do, what is untested, and what you assumed.
The full rules are in §8 of the manual.
