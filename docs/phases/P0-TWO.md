# P0 · Person Two (Windows) — Foundations

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P0`, you are in the wrong file.
> If `owner` is not `person_two`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P0 — Foundations |
| **Gate** | G0 |
| **Duration** | ~1 week |
| **You own** | public web, admin console, contracts, fixtures, QA, security testing |
| **Your directories** | `/web, /tests, /fixtures, /design` |
| **You never** | Xcode, SwiftUI builds, Keychain implementation, TestFlight, Apple signing, APNs certificates, production database access, or any change to /backend, /ios, /infra, /db |
| **Manual section** | §27.1 |
| **Other lane** | `docs/phases/P0-ONE.md` |

**Outcome this phase must reach**
The real app performs a real HTTP call to real staging and renders the response, and both people can find that same request in the logs.

**Why it matters**
Nothing else in this manual works until the communication path is proven. Every later phase assumes that a request leaves a device, reaches a service, is logged with a correlation ID, and comes back in a shape both lanes agreed on. Building features before that is building on an assumption.

Everything in this file runs on Windows. If a task here appears to need a Mac, it has been written wrong — raise it rather than working around it.

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

```powershell
docker compose up -d postgres redis
pnpm install
pnpm --filter @plug/web dev          # http://localhost:3000
Push-Location tests/api
bru run --env local
Pop-Location
pnpm --filter @plug/web test:e2e
```

If any of those commands fails on a clean machine, that is a bug in
`docs/onboarding/windows.md`, and fixing the
documentation is part of the work.

---

## 2. Your steps

Each line is one state token. Do them in order, update `PROJECT_STATE.json` as
you go, and open one pull request per step or per small group of related steps.

- [ ] **P0.S1** — Clone the repository on Windows and prove the documented Windows setup works end to end from a clean machine. Fix `docs/onboarding/windows.md` wherever it does not.
- [ ] **P0.S2** — Initialise `/web` with the TypeScript and Next.js structure: the public site and a protected admin shell. Do not build feature UI yet.
- [ ] **P0.S3** — Create `/design/tokens.json` from §10.1 and the generator that produces the CSS and Swift token files.
- [ ] **P0.S4** — Create the Playwright baseline with a smoke test that loads the public shell and asserts the protected route redirects.
- [ ] **P0.S5** — Create the `/tests/api` Bruno collection for `GET /health` and the `POST /v1/requests` stub, including the validation-error case.
- [ ] **P0.S6** — Review the OpenAPI examples and create the success, validation-error, authorization-error and transient-error fixtures under `/fixtures`.
- [ ] **P0.S7** — Create the Figma implementation checklist mapping screens and components to future phases. Do not invent screens outside this manual.
- [ ] **P0.S8** — Document every Windows installation step, including WSL2 and Docker Desktop, in `docs/onboarding/windows.md`.
- [ ] **P0.S9** — Set up the shared tracker with the security-owner and incident-contact fields.

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

Verify with:

```powershell
pnpm --filter @plug/web lint
pnpm --filter @plug/web build          # includes TypeScript checking
pnpm --filter @plug/web test:e2e
Push-Location tests/api
bru run --env local
Pop-Location
```

Bruno must run inside `tests/api`. The temporary public checkpoint uses the
public-only command in ADR-004, with Person One's current tunnel URL; readiness
remains a direct local check. There is no `test:unit` script or `tests/api/abuse`
folder yet; required abuse evidence still needs actual cases and results.

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
