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
# From the repository root, after completing docs/onboarding/mac.md:
set -a
source .env.local
set +a
docker compose --env-file .env.local up -d --wait postgres redis
cd backend
./dev bootRun --args='--spring.profiles.active=db'
# Flyway migrations run at startup. Leave this terminal running.
# In a second terminal at the repository root:
open ios/Plug.xcodeproj             # scheme: Plug
```

If any of those commands fails on a clean machine, that is a bug in
`docs/onboarding/mac.md`, and fixing the
documentation is part of the work.

---

## 2. Your steps

Each line is one state token. Do them in order, update `PROJECT_STATE.json` as
you go, and open one pull request per step or per small group of related steps.

- [x] **P1.S1** — Freeze the auth OpenAPI: Apple, phone start and verify, guest, refresh and session rules, logout, errors and consent version.
- [x] **P1.S2** — Implement Apple token verification server-side, and the Sign in with Apple client flow in iOS.
- [x] **P1.S3** — Implement phone verification with per-IP and per-identity rate limits, attempt limits, expiry and audit events.
- [x] **P1.S4** — Implement guest identity and the upgrade-and-link behaviour, without losing the current request context.
- [x] **P1.S5** — Create the `users`, `identities`, `sessions` and `consents` migrations.
- [x] **P1.S6** — Store iOS credentials in the Keychain per §20.2. Ensure tokens never appear in logs, analytics or crash breadcrumbs.
- [x] **P1.S7** — Use short-lived access tokens and rotating refresh sessions; store refresh material server-side in a revocable form.
- [x] **P1.S8** — Implement session revocation on logout, account deletion and any security-sensitive change.
- [x] **P1.S9** — Add deny-by-default auth middleware and a resource-level authorization test endpoint.
- [x] **P1.S10** — Require MFA for admin access before any production or beta admin mutation is enabled.
- [x] **P1.S11** — Build the welcome, sign-in and create-account screens, with invalid code, expired code, offline, denied-notification and account-link-conflict states.
- [x] **P1.S12** — Add the Terms and Privacy links and the consent copy to the onboarding flow.

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

- [x] Replayed and expired Apple token tests — `backend .../identity/AppleSignInTest.java`
- [x] Phone brute-force and rate-limit tests — `PhoneVerificationTest.java`
- [x] Keychain persistence and logout tests — `ios/PlugTests/KeychainStoreTests.swift`, `SessionStoreTests.swift`
- [x] Guest restriction and upgrade tests — `GuestAndUpgradeTest.java`
- [x] IDOR and auth-bypass tests on a protected endpoint — `SessionLifecycleTest.java`
- [x] Refresh-token rotation and replay test: a reused rotated token is rejected and the affected chain is revoked — `SessionLifecycleTest.java`
- [x] BOLA test across user and admin resource IDs — `SessionLifecycleTest.java`. Supplier
      resources do not exist until Phase 3, so that third identifier class is not covered
      here and must be added with the supplier module.
- [x] Log inspection confirms no access token, refresh token, OTP secret or authorization header is emitted — `AuthLoggingTest.java`

Verify with:

```bash
# The identity tests need a real database and the pepper the db profile requires.
docker compose --env-file .env.local up -d --wait postgres
cd backend
./dev check                                  # Phase 0 suite, contract tests, checkstyle
PLUG_DATABASE_PASSWORD=... PLUG_IDENTITY_PEPPER=... ./dev databaseTest

cd ..
xcodebuild -showdestinations -project ios/Plug.xcodeproj -scheme Plug
# Choose an installed simulator UUID from the output above. Ad-hoc signing is what gives
# the app an entitlement; without it the Keychain tests can only skip.
xcodebuild test -project ios/Plug.xcodeproj -scheme Plug \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

`ContractTest` runs in the normal backend test task; there is no separate
`contractTest` task or `ArchitectureTest` class yet.

With a backend running, two more things can be checked end to end:

```bash
# The whole auth surface, 35 assertions, against a real database
sh tools/phase1-auth-walkthrough.sh

# The sign-in screens, photographed at both text sizes. Run this against a real
# iPhone before the gate: the same test, and then the output IS the §12.3 evidence.
xcodebuild test -project ios/Plug.xcodeproj -scheme Plug -only-testing:PlugUITests \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

`LiveBackendTests` joins the normal run whenever a backend is answering on
`127.0.0.1:8080`, and skips when one is not. It prints the correlation ids to
search for in the backend log.

Passing all of the above does not pass the gate. The Apple path has to be run on
a real physical device, force-quit and relaunched, before anyone claims the
session survives a relaunch — and two people have to see it.

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

> The step-by-step version of everything below, including what is still
> outstanding and who has to be in the room for it, is
> `docs/runbooks/p1-gate-completion.md`.


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

## 9. Contributor handoff

Read `PROJECT_STATE.json` and confirm the current phase, step, owner and next
accepted task before making changes. Coordinate changes to another engineer's
paths. Propose contract changes before adding fields, endpoints, enums or error
codes. Record verification, outstanding work and assumptions in the PR.
Follow [the contributor workflow](../CONTRIBUTOR_WORKFLOW.md).
