# P2 · Person Two (Windows) — Ask, parse, clarify, progress and seeded results

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P2`, you are in the wrong file.
> If `owner` is not `person_two`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P2 — Ask, parse, clarify, progress and seeded results |
| **Gate** | G2 |
| **Duration** | ~1.5 weeks |
| **You own** | public web, admin console, contracts, fixtures, QA, security testing |
| **Your directories** | `/web, /tests, /fixtures, /design` |
| **You never** | Xcode, SwiftUI builds, Keychain implementation, TestFlight, Apple signing, APNs certificates, production database access, or any change to /backend, /ios, /infra, /db |
| **Manual section** | §27.3 |
| **Other lane** | `docs/phases/P2-ONE.md` |

**Outcome this phase must reach**
“I need to repair my shoe for $45 tomorrow, who is available?” — or “Barber under $35 in 30 minutes” — produces validated structured results with honest progress, at most one clarifying question, and no fabricated values anywhere.

> **Redesigned to manual v4 ([ADR-010](../decisions/ADR-010-manual-v4-asks-skills-providers.md), 2026-10-02, proposed).**
> Two kinds of ask in one field, a controlled skill vocabulary you own, providers on the
> same account. ADR-009's Apple Maps listing and free-form categories are withdrawn.
> Person One drafted some of your v4 artefacts so neither lane waits; each is marked below
> and is yours to review, change or reject in the 0.5.0 contract session.

**Why it matters**
This is where the product becomes itself. It is also where the temptation to let the model decide things is strongest, and where a single fabricated price would undermine the entire premise.

Everything in this file runs on Windows. If a task here appears to need a Mac, it has been written wrong — raise it rather than working around it.

---

## 0. Before any code — the contract

This phase does not start with code. It starts with a fifteen-minute session
with the other person, which produces one merged pull request in `/contracts`
covering:

- `POST /v1/requests` and the full `Request` schema
- `POST /v1/requests/{id}/clarifications`
- `GET /v1/requests/{id}` and `GET /v1/requests/{id}/offers`
- The `status` and `next_action` enums
- The location object, money units and timestamp format

Nothing below this line begins until that pull request has merged with both
approvals. If you find yourself writing an endpoint that is not in the contract,
stop and open a contract pull request instead.

Contract-review preparation on 2026-10-01: P2.S1 response fixtures and the labelled
dataset are prepared alongside the proposal, as requested in `PROJECT_STATE.json`.
They remain subject to both approvals. See [the hardening record](../testing/phase2-person-two-hardening-2026-10-01.md).
P2.S2 live tests and later implementation are still gated on the contract merge.

---

## 1. Environment

```powershell
pnpm install --frozen-lockfile
pnpm test:contracts                 # fixtures and dataset, no backend required
pnpm --filter @plug/web dev          # http://localhost:3000
# Stop the interactive server when finished. Playwright owns localhost:3100.
pnpm --filter @plug/web test:e2e
```

For the database, identity secret, backend and locked Bruno CLI, follow
[Windows onboarding](../onboarding/windows.md). There is no standing staging URL;
use the current checkpoint tunnel as described in `tests/api/environments/README.md`.

If any of those commands fails on a clean machine, that is a bug in
`docs/onboarding/windows.md`, and fixing the
documentation is part of the work.

---

## 2. Your steps

Each line is one state token. Do them in order, update `PROJECT_STATE.json` as
you go, and open one pull request per step or per small group of related steps.

- [ ] **P2.S1** — Create and maintain the labelled intent and edge-case dataset, and the shared fixtures under `/fixtures`. Prepared and locally validated; contract review/merge pending.
- [ ] **P2.S2** — Build the Bruno contract tests for request creation, clarification, polling and status, offers, cancellation, and every documented error.
- [ ] **P2.S3** — Review Figma for anti-vibecode compliance per §16: typography, spacing, no gradients, no glass, no pills, no fake proof, and every required state present.
- [ ] **P2.S4** — Build a web-based internal request inspector only if QA needs it; it must consume real staging data and must not duplicate canonical logic.
- [ ] **P2.S5** — *Drafted by Person One: `docs/runbooks/phase2-asking-guide.md` (what people can ask, limits, refusals, no-coverage behaviour) — review and own.* — Document the exact supported launch request grammar and the unsupported-category behaviour, for QA and support.
- [ ] **P2.S6** — Run the API abuse cases: overlong prompt, invalid coordinates, absurd budget, malformed timestamps, repeated submissions, and rate-limit behaviour.
- [ ] **P2.S7** — Build the labelled classification dataset: service asks, place questions, ambiguous asks and restricted asks, with the expected `ask_type`. *Drafted by Person One: `fixtures/intents/p2.jsonl` (46 vectors, re-labelled against the vocabulary) — review and extend.*
- [ ] **P2.S8** — Own the skill vocabulary in `contracts/skills.yaml`. *Drafted by Person One: 35 tags; childcare, elder care, medical, legal and financial advice deliberately absent. Yours from here; every change is a PR plus a migration.*
- [ ] **P2.S9** — Bruno suite for the two-pipeline classifier, including refusals and clarifications. *Drafted by Person One: `tests/phase2/38`–`47` (asks, private place, restricted, foreign ask, provider propose/licence/unknown tag/save).*
- [ ] **P2.S10** — Review the Ask screen against Figure A1 and the design gate. Simulator captures: `evidence/P2/simulator/2026-10-02/`.
- [ ] **P2.S11** — Abuse cases the open scope requires: illegal goods or services, targeting a private person, surveillance in disguise, regulated professions.
- [ ] **P2.S12** — *Backend ready (5 October): `GET /v1/admin/skills`, `/skills/gaps`, `/classifications`, `/refusals` with fixtures in `fixtures/admin.*`. Staff sign-in exists from 5 October (ADR-013, contract 0.6.0): `POST /v1/staff/login`, `/v1/staff/login/verify`, `/v1/staff/invites/accept`, and owner management under `/v1/admin/staff`; `node tools/staff.mjs` until the web console has these screens.* — Admin view for the skill vocabulary and recent classifier decisions (`vocabulary_gaps` and the `restricted_intent:<rule>` audit events are the data).
- [ ] **Web v4 retheme** — Owner-authorized temporary implementation now uses Public Sans, sentence-case labels and dashed Not verified. 81 Playwright tests passed; screenshots at 320/360/768/1280 px are in `evidence/P2/web/2026-10-02/ui-experiment/`. Review the [hardening record](../testing/phase2-hardening-ui-experiment-2026-10-02.md). The old draft patch is historical; do not apply it over this work.

---

## 3. When you work with the other person

1. The contract session for the Request schema — this is the most consequential contract in the product.
2. The design checkpoint for Ask, clarification, progress and results copy.
3. The connected checkpoint, to run the labelled dataset against real staging.

Outside these moments, work asynchronously. The fixtures in `/fixtures` are the
shared truth while the lanes are split — not a screenshot, not a message, not a
verbal description.

---

## 4. Tests that must pass

- [ ] Intent-extraction tests across the labelled dataset, including deliberately ambiguous input.
- [ ] State-machine legal-transition tests, including every illegal transition.
- [ ] Clarification logic tests: exactly one blocking question, never two.
- [ ] Contract tests for every documented response and error.
- [ ] Race and cancellation tests: cancelling mid-flight is safe and idempotent.
- [ ] Model-provider failure test: a timeout or invalid schema produces the deterministic fallback, not a 500.
- [ ] Restricted-intent test: a prohibited request creates no outreach and writes an audit event.
- [ ] Open-service test: any lawful service (e.g. shoe repair) is accepted, and Claude output that fails validation falls back to the rules.

Verify with:

```powershell
pnpm --filter @plug/web typecheck
pnpm --filter @plug/web lint
pnpm --filter @plug/web test:unit
pnpm --filter @plug/web test:e2e
```

`test:unit` runs the shared static contract/fixture/dataset checks. It does not
execute the future intent adapter. The existing `tests/api/requests-create-*.bru`
files exercise the Phase 0 stub; do not present them as Phase 2 acceptance.
P2.S2 must add the real request collection and P2.S6 the abuse cases after contract
merge and backend availability; `tests/api/abuse` does not exist yet. The full
phase requires the connected evidence listed below, beyond these local checks.

---

## 5. Gate G2 — what the reviewer checks

- [ ] Input schema rejects malformed and oversized values before business logic runs.
- [ ] AI and model output is schema-validated before persistence.
- [ ] No raw model reasoning is shown to users anywhere.
- [ ] Results use Confirmed, Recent, Estimated and Unknown correctly, set server-side.
- [ ] No horizontal overflow and no broken Dynamic Type state in iOS.
- [ ] Race and cancellation behaviour is safe and idempotent.

---

## 6. Exit criteria — what is true when this phase is over

- [ ] A supported request produces validated structured offers on a real device.
- [ ] Progress counts are real and visibly change as the server works.
- [ ] A service with no participating supplier ends `no_coverage` honestly, with no invented prices or availability; v4 removes the Apple Maps listing fallback.
- [ ] A provider failure degrades to the deterministic path without an error screen.
- [ ] `PROJECT_STATE.json` carries a signed `G2` entry.

---

## 7. Evidence to commit before the gate

Store everything under `evidence/P2/`:

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
4. Append the `G2` entry to `gate_log` in `PROJECT_STATE.json`, with both
   signatures, the evidence path and any known limitation.
5. Set `current_phase` to the next phase and rewrite `next_actions`.
6. Book the next phase's contract session before you close the laptop.

**Watch:** Person Two must not hardcode status strings in the web console. Consume the generated enum, so an added state breaks the build rather than rendering an empty screen.

---

## 9. Contributor handoff

Read `PROJECT_STATE.json` and confirm the current phase, step, owner and next
accepted task before making changes. Coordinate changes to another engineer's
paths. Propose contract changes before adding fields, endpoints, enums or error
codes. Record verification, outstanding work and assumptions in the PR.
Follow [the contributor workflow](../CONTRIBUTOR_WORKFLOW.md).
