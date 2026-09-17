# P1 · Person One (MacBook) — Identity and consent

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P1`, you are in the wrong file.
> If `owner` is not `person_one`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P1 — Identity and consent |
| **Gate** | G1 |
| **Duration** | ~1 week |
| **You own** | backend, iOS, infrastructure, production |
| **Your directories** | `/backend, /ios, /infra, /db` |
| **You never** | nothing is off-limits, but /web, /tests, /fixtures and /design belong to Person Two — request changes there rather than making them |
| **Manual section** | §27.2 |
| **Other lane** | `docs/phases/P1-TWO.md` |

**Outcome this phase must reach**
A real user signs in with Apple on a real device, the session survives a relaunch, logout revokes the session server-side, and no token appears in any log.

**Why it matters**
Identity is the first thing that carries real consequences. Every later authorization check, every audit event and every consent record depends on there being exactly one identity model, established now and not invented a second time in Phase 3.

You are the final technical authority on this phase. If something here conflicts with a decision Person Two made in the web lane, the contract decides — not seniority.

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

- [ ] **P1.S1** — Freeze the auth OpenAPI: Apple, phone start and verify, guest, refresh and session rules, logout, errors and consent version.
- [ ] **P1.S2** — Implement Apple token verification server-side, and the Sign in with Apple client flow in iOS.
- [ ] **P1.S3** — Implement phone verification with per-IP and per-identity rate limits, attempt limits, expiry and audit events.
- [ ] **P1.S4** — Implement guest identity and the upgrade-and-link behaviour, without losing the current request context.
- [ ] **P1.S5** — Create the `users`, `identities`, `sessions` and `consents` migrations.
- [ ] **P1.S6** — Store iOS credentials in the Keychain per §20.2. Ensure tokens never appear in logs, analytics or crash breadcrumbs.
- [ ] **P1.S7** — Use short-lived access tokens and rotating refresh sessions; store refresh material server-side in a revocable form.
- [ ] **P1.S8** — Implement session revocation on logout, account deletion and any security-sensitive change.
- [ ] **P1.S9** — Add deny-by-default auth middleware and a resource-level authorization test endpoint.
- [ ] **P1.S10** — Require MFA for admin access before any production or beta admin mutation is enabled.
- [ ] **P1.S11** — Build the welcome, sign-in and create-account screens, with invalid code, expired code, offline, denied-notification and account-link-conflict states.
- [ ] **P1.S12** — Add the Terms and Privacy links and the consent copy to the onboarding flow.

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

```bash
./gradlew :backend:test :backend:contractTest
./gradlew :backend:test --tests '*ArchitectureTest'
xcodebuild test -scheme PLUG-Staging -destination 'platform=iOS Simulator,name=iPhone 15'
# Then, on a REAL device, run this phase's primary flow before claiming it works.
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
