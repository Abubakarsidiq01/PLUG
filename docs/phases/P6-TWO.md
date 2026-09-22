# P6 · Person Two (Windows) — Beta hardening and release readiness

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P6`, you are in the wrong file.
> If `owner` is not `person_two`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P6 — Beta hardening and release readiness |
| **Gate** | G6 |
| **Duration** | ~1.5 weeks |
| **You own** | public web, admin console, contracts, fixtures, QA, security testing |
| **Your directories** | `/web, /tests, /fixtures, /design` |
| **You never** | Xcode, SwiftUI builds, Keychain implementation, TestFlight, Apple signing, APNs certificates, production database access, or any change to /backend, /ios, /infra, /db |
| **Manual section** | §27.7 |
| **Other lane** | `docs/phases/P6-ONE.md` |

**Outcome this phase must reach**
Backup restore proven, rollback rehearsed, load and dependency-failure drills passed, the full security and accessibility sweep clean, and zero open critical or high findings without a dated exception.

**Why it matters**
This is the phase that decides whether the beta is a product or a demonstration. Everything here is a drill, and a drill that has not been run has not passed.

Everything in this file runs on Windows. If a task here appears to need a Mac, it has been written wrong — raise it rather than working around it.

---

## 0. Before any code — the contract

This phase does not start with code. It starts with a fifteen-minute session
with the other person, which produces one merged pull request in `/contracts`
covering:

- No new contracts. Only versioned corrections found during hardening.

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

- [ ] **P6.S1** — Run the full Playwright E2E suite across every supported desktop and mobile viewport; eliminate all horizontal overflow.
- [ ] **P6.S2** — Run broken-link checks, functional navigation, mobile menu, clickable logo, tel and mailto links, footer and custom 404 checks.
- [ ] **P6.S3** — Run Lighthouse and Core Web Vitals review, image compression review, alt-text audit and JavaScript bundle review for the public site.
- [ ] **P6.S4** — Finish dynamic page titles, meta descriptions, the Open Graph image, `sitemap.xml`, `robots.txt` and canonical metadata.
- [ ] **P6.S5** — Ensure admin and private routes are noindex and cannot leak protected content into static or client output.
- [ ] **P6.S6** — Implement cookie consent only for non-essential trackers actually in use; avoid a meaningless banner where consent is not required.
- [ ] **P6.S7** — Run OWASP ZAP and browser security checks, dependency and SCA scans, secret checks and exposed-file checks. File every finding.
- [ ] **P6.S8** — Run form spam and validation tests, success and error feedback tests, and analytics event verification without sensitive content.
- [ ] **P6.S9** — Review all public copy for fake metrics, fake reviews, placeholders, vague buzzwords and unsupported claims.

---

## 3. When you work with the other person

1. Throughout — this phase is closer to equal effort than any other.
2. The failure-matrix review, jointly, running every drill in §29.
3. The release gate itself.

Outside these moments, work asynchronously. The fixtures in `/fixtures` are the
shared truth while the lanes are split — not a screenshot, not a message, not a
verbal description.

---

## 4. Tests that must pass

- [ ] Load test at expected beta traffic and at three times expected traffic.
- [ ] Webhook burst test.
- [ ] Database saturation and slow-query test.
- [ ] Queue backlog and poison-message test.
- [ ] Dependency failure and circuit-breaker test for Twilio, the model provider and Places.
- [ ] Backup restore drill with measured RPO and RTO.
- [ ] Rollback rehearsal with a real deployment.
- [ ] Full accessibility sweep on both surfaces.
- [ ] Full external security scan.

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

## 5. Gate G6 — what the reviewer checks

- [ ] Any unresolved critical or high security finding without an approved, dated mitigation blocks release.
- [ ] Any false booking, false Confirmed or false NOW truth state blocks release.
- [ ] Backup restore not proven blocks release.
- [ ] Any critical auth, IDOR or rate-limit failure blocks release.
- [ ] A production secret exposed to the frontend, the repository or a log blocks release.
- [ ] A core user journey crash or unrecoverable error blocks release.
- [ ] A broken legal or privacy path blocks release.
- [ ] Material mobile overflow or an inaccessible primary action on web blocks release.
- [ ] No rollback path for the release candidate blocks release.

---

## 6. Exit criteria — what is true when this phase is over

- [ ] Every drill in §29 has been run and recorded.
- [ ] Restore and rollback are proven, with measured numbers.
- [ ] Both surfaces pass accessibility and security sweeps.
- [ ] The TestFlight build is ready with accurate privacy disclosures.
- [ ] `PROJECT_STATE.json` carries a signed `G6` entry.

---

## 7. Evidence to commit before the gate

Store everything under `evidence/P6/`:

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
4. Append the `G6` entry to `gate_log` in `PROJECT_STATE.json`, with both
   signatures, the evidence path and any known limitation.
5. Set `current_phase` to the next phase and rewrite `next_actions`.
6. Book the next phase's contract session before you close the laptop.

**Watch:** The temptation at this gate is to accept a finding “for now” without a date. An exception without an expiry is not an exception; it is a decision to ship the problem permanently.

---

## 9. Contributor handoff

Read `PROJECT_STATE.json` and confirm the current phase, step, owner and next
accepted task before making changes. Coordinate changes to another engineer's
paths. Propose contract changes before adding fields, endpoints, enums or error
codes. Record verification, outstanding work and assumptions in the PR.
Follow [the contributor workflow](../CONTRIBUTOR_WORKFLOW.md).
