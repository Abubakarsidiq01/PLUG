# P0 · Person One (MacBook) — Foundations

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P0`, you are in the wrong file.
> If `owner` is not `person_one`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P0 — Foundations |
| **Gate** | G0 |
| **Duration** | ~1 week |
| **You own** | backend, iOS, infrastructure, production |
| **Your directories** | `/backend, /ios, /infra, /db` |
| **You never** | nothing is off-limits, but /web, /tests, /fixtures and /design belong to Person Two — request changes there rather than making them |
| **Manual section** | §27.1 |
| **Other lane** | `docs/phases/P0-TWO.md` |

**Outcome this phase must reach**
The real app performs a real HTTP call to real staging and renders the response, and both people can find that same request in the logs.

**Why it matters**
Nothing else in this manual works until the communication path is proven. Every later phase assumes that a request leaves a device, reaches a service, is logged with a correlation ID, and comes back in a shape both lanes agreed on. Building features before that is building on an assumption.

You are the final technical authority on this phase. If something here conflicts with a decision Person Two made in the web lane, the contract decides — not seniority.

---

## 0. Before any code — the contract

This phase does not start with code. It starts with a fifteen-minute session
with the other person, which produces one merged pull request in `/contracts`
covering:

- Repository layout, branch rules and required checks
- `GET /health` and `GET /health/ready` response shapes
- `POST /v1/requests` stub: request, response and the error envelope
- Environment names, base URLs and the correlation-ID header

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

- [ ] **P0.S1** — Create the monorepo with the layout in §17.3, plus `CODEOWNERS`, `.gitattributes`, `.editorconfig` and branch protections.
- [ ] **P0.S2** — Initialise the Spring Boot 3 / Java 21 modular-monolith skeleton with Gradle, Actuator, validation, JPA, Flyway, the PostgreSQL driver and the test dependencies.
- [ ] **P0.S3** — Implement `GET /health` and `GET /health/ready`, the structured error envelope from §18.2, and the correlation filter from §19.2.
- [ ] **P0.S4** — Implement `POST /v1/requests` as a validated stub, per the frozen contract. No business logic beyond validation and a shaped response.
- [ ] **P0.S5** — Provision local PostgreSQL with PostGIS through Docker Compose, and the staging database and network baseline. Keep the database private.
- [ ] **P0.S6** — Create the Terraform skeleton, environment naming, base URLs and the secret-storage plan.
- [ ] **P0.S7** — Create the Xcode SwiftUI project under `/ios`, with environment configuration, the `APIClient` from §20.2 and a temporary engineering health screen.
- [ ] **P0.S8** — Add GitHub Actions for backend build, test and migration validation, and an iOS build and unit-test job on a macOS runner.
- [ ] **P0.S9** — Enable the security baseline: secret scanning, dependency scanning, environment validation, staging TLS and safe logging.
- [ ] **P0.S10** — Write the first threat model and data-classification note in `/docs/security`.
- [ ] **P0.S11** — Add bounded HikariCP settings, request and query timeouts, graceful shutdown and readiness behaviour.
- [ ] **P0.S12** — Create `PROJECT_STATE.json` with `current_phase: P0` and an empty `gate_log`.

---

## 3. When you work with the other person

1. The contract session, before either person writes code — OpenAPI and the error envelope are frozen there.
2. The first time a staging endpoint is reachable, for API testing.
3. The Phase 0 checkpoint, to compare request IDs across the two logs.

Outside these moments, work asynchronously. The fixtures in `/fixtures` are the
shared truth while the lanes are split — not a screenshot, not a message, not a
verbal description.

---

## 4. Tests that must pass

- [ ] Backend unit tests for health and the error envelope.
- [ ] Contract test validating the stub response against OpenAPI.
- [ ] iOS decoding test using the shared fixture.
- [ ] Staging smoke test from a physical iPhone.
- [ ] WAF or rate-limit smoke test returns a controlled 429 without crashing the API.
- [ ] Database and Redis are confirmed unreachable directly from the public internet.
- [ ] Log inspection confirms no secret, authorization header or phone number appears in structured logs.
- [ ] Connection-pool exhaustion and slow-query behaviour fail safely rather than exhausting the service.

Verify the existing baseline with:

```bash
(cd backend && ./dev check)
xcodebuild -showdestinations -project ios/Plug.xcodeproj -scheme Plug
# Choose an installed simulator UUID from the output above:
xcodebuild test -project ios/Plug.xcodeproj -scheme Plug \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UUID'
```

`ContractTest` runs in the normal backend test task; there is no separate
`contractTest` task or `ArchitectureTest` class yet. The database failure/recovery checks run through `./dev databaseTest` against a real local PostgreSQL instance; see the closeout evidence.

---

## 5. Gate G0 — what the reviewer checks

- [ ] No secret in the repository or the frontend bundle; environment validation fails closed.
- [ ] Database and cache are not publicly reachable.
- [ ] Health and readiness are separate; the public health response leaks no configuration.
- [ ] Structured logs redact credentials and carry a correlation ID.
- [ ] CI runs at least dependency, secret, and build-and-test checks.
- [ ] Request-size and timeout settings are defined before any public exposure.

---

## 6. Exit criteria — what is true when this phase is over

- [ ] A clean clone works for the Mac lane and the Windows lane, from the documented steps alone.
- [ ] `main` is protected and CODEOWNERS is active.
- [ ] A real iPhone reaches staging and renders a known response.
- [ ] The Windows web shell runs and the Bruno collection passes against staging.
- [ ] No high or critical security issue is open.
- [ ] `PROJECT_STATE.json` carries a signed `G0` entry.

---

## 7. Evidence to commit before the gate

Store everything under `evidence/P0/`:

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
4. Append the `G0` entry to `gate_log` in `PROJECT_STATE.json`, with both
   signatures, the evidence path and any known limitation.
5. Set `current_phase` to the next phase and rewrite `next_actions`.
6. Book the next phase's contract session before you close the laptop.

**Watch:** If Person One changes the error envelope after this phase, every fixture and both clients change with it. Freeze it properly now — this is the cheapest moment to get it right.

---

## 9. Contributor handoff

Read `PROJECT_STATE.json` and confirm the current phase, step, owner and next
accepted task before making changes. Coordinate changes to another engineer's
paths. Propose contract changes before adding fields, endpoints, enums or error
codes. Record verification, outstanding work and assumptions in the PR.
Follow [the contributor workflow](../CONTRIBUTOR_WORKFLOW.md).
