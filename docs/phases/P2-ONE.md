# P2 · Person One (MacBook) — Ask, parse, clarify, progress and seeded results

> **Before you start:** read `PROJECT_STATE.json` at the repository root.
> If `current_phase` is not `P2`, you are in the wrong file.
> If `owner` is not `person_one`, check `next_actions` — there may
> still be an entry assigned to you further down the list.

| | |
|---|---|
| **Phase** | P2 — Ask, parse, clarify, progress and seeded results |
| **Gate** | G2 |
| **Duration** | ~1.5 weeks |
| **You own** | backend, iOS, infrastructure, production |
| **Your directories** | `/backend, /ios, /infra, /db` |
| **You never** | nothing is off-limits, but /web, /tests, /fixtures and /design belong to Person Two — request changes there rather than making them |
| **Manual section** | §27.3 |
| **Other lane** | `docs/phases/P2-TWO.md` |

**Outcome this phase must reach**
“I need to repair my shoe for $45 tomorrow, who is available?” — or “Barber under $35 in 30 minutes” — produces validated structured results with honest progress, at most one clarifying question, and no fabricated values anywhere.

> **Redesigned to manual v4 ([ADR-010](../decisions/ADR-010-manual-v4-asks-skills-providers.md), 2026-10-02, proposed).**
> One field takes two kinds of ask: a service request or a question about a public place.
> Skills come only from `contracts/skills.yaml`; the restricted-intent policy is the only
> refusal; any account can add provider skills. Design follows manual v4 §10 and Figures
> A1–A3: ink on paper, no brand colour. Contract 0.5.0 supersedes the unmerged 0.4.0.
> [ADR-009](../decisions/ADR-009-open-service-scope.md)'s Apple Maps listing and free-form
> categories are withdrawn; its Claude extraction and budget rules stand.

**Why it matters**
This is where the product becomes itself. It is also where the temptation to let the model decide things is strongest, and where a single fabricated price would undermine the entire premise.

You are the final technical authority on this phase. If something here conflicts with a decision Person Two made in the web lane, the contract decides — not seniority.

---

## Carried in from Phase 1

Written when Phase 1 closed, so the decisions that constrain this phase are here
rather than in somebody's memory.

- **One identity, for the life of the account.** Key everything to
  `account.user_id` from `GET /v1/me`. A guest is a real account with a real
  user id, and upgrading to Apple or a phone keeps that id — which is the whole
  reason a request started as a guest survives sign-in. Do not introduce a
  second client identity (manual.docx §27.2 handoff note).
- **Authorization is deny-by-default.** A route that is not named in
  `identityRules()` in `SecurityConfiguration` is refused. That is intended: a
  new endpoint fails closed until somebody writes its rule. Add the rule in the
  same change as the route.
- **Ownership is checked per resource, and a denial is a 404.** Follow
  `MeController` and `SessionService.requireOwned`: take the owner from the
  authenticated principal, never from the request, and answer 404 rather than
  403 so an identifier cannot be confirmed by probing.
- **Add new routes to `CorrelationFilter.safePath()`**, or they log as
  `unmapped`. Paths carrying an identifier are logged as their template — see
  how `/v1/me/sessions/{session_id}` is handled — so the id stays out of the log.
- **The error-code enum is frozen.** Branch clients on
  `error.details[].code` tokens rather than adding a new top-level code. Phase 1
  did this for invalid and expired one-time codes.
- **Recheck the tab bar on physical devices.** Phase 1 fixed the missing launch-screen declaration that squeezed the app into a 320×480 compatibility window. The September 23 simulator captures use the full display; confirm labels and navigation with real-device Dynamic Type and VoiceOver before changing tab names.


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

---

## 1. Environment

Follow [the isolated Phase 2 runbook](../runbooks/phase2-local.md) to create
`plug_phase2_tests` and `plug_phase2_live`. Automated database tests erase test data;
never point them at the phone's live database.

```bash
sh tools/run-phase2-local.sh      # loopback port 18080; migrations run at startup
open ios/Plug.xcodeproj           # scheme: Plug
# Or build/install using the private paired-device connection:
sh tools/run-phase2-phone.sh
```

If any of those commands fails on a clean machine, that is a bug in
`docs/onboarding/mac.md`, and fixing the
documentation is part of the work.

---

## 2. Your steps

Person One hardening and current verification: [2026-10-04 report](../testing/phase2-person-one-hardening-2026-10-04.md). Implementation checks pass locally; open boxes below also require the actual shared approvals and device evidence, so they are not a claim that the code is missing.

Each line is one state token. Do them in order, update `PROJECT_STATE.json` as
you go, and open one pull request per step or per small group of related steps.

- [ ] **P2.S1** — Freeze the Request, constraints, status, next_action, location, money and timestamp contracts.
- [ ] **P2.S2** — Implement the intent adapter with strict structured output and deterministic validation, per §19.5. Treat model output as untrusted.
- [ ] **P2.S3** — Create the request state machine with legal-transition tests and idempotent cancellation, per §19.6.
- [ ] **P2.S4** — Create the `requests`, `request_constraints`, `places` and supplier-seed migrations with the required indexes.
- [ ] **P2.S5** — Implement the clarification decision: ask only when a missing field genuinely blocks execution, and never more than one question.
- [ ] **P2.S6** — Expose real progress counts and `next_action`. No client-side timers pretending to be progress.
- [ ] **P2.S7** — Return only structured, validated seeded offers. The app never fabricates price, availability, wait or confirmation.
- [ ] **P2.S8** — Add request-creation rate limits, request-size limits and restricted-intent policy enforcement.
- [ ] **P2.S9** — Build the SwiftUI Ask, clarification, progress, results and offer-detail screens from Figma, including the offline, no-match, parser-error and cached states.

Manual v4 adds ten steps. Implemented and verified locally on 2026-10-02 behind
`requests_v2`; every box stays open until contract 0.5.0 is approved by both engineers and
G2 is signed. Evidence: `docs/testing/phase2-v4-verification-2026-10-02.md`.

- [ ] **P2.S10** — Freeze the AskEnvelope: one endpoint accepts both kinds of ask. The server classifies into `service_request` or `place_question` and returns `ask_type`. *(Proposed in 0.5.0: `POST /v1/asks`, `GET /v1/asks/{ask_id}`, `POST /v1/asks/{ask_id}/clarifications`.)*
- [ ] **P2.S11** — Classifier with strict structured output and a deterministic fallback. An unclassifiable ask returns one clarifying question, never a guess. *(`IntentAdapter`, `ClaudeIntentProvider`.)*
- [ ] **P2.S12** — Extract skill tags against the controlled vocabulary; it grows by migration, never by model invention. *(`SkillVocabulary`, V6 seeds `skill_vocabulary`; startup fails if it disagrees with `skills.yaml`.)*
- [ ] **P2.S13** — Remove every remaining category allow-list. Scope is any lawful service and any public place.
- [ ] **P2.S14** — Restricted-intent policy as the only block, stricter because scope is open. Runs before any model call; refusals are audited. *(`RestrictedIntentPolicy`.)*
- [ ] **P2.S15** — `POST /v1/providers/skills`: a normal user adds skills, radius and availability to the same account. *(`ProviderService`; also `/propose` and `/me`.)*
- [ ] **P2.S16** — `provider_profiles`, `provider_skills`, `skill_vocabulary`, `provider_availability` migrations. *(V6, with `provider_scores`, `request_matches`, `asks`, `place_questions`, `vocabulary_gaps`.)*
- [ ] **P2.S17** — Matching: skill overlap, inside the provider's own radius, inside their availability; ranked per §19A; fanout 6, cap 16; never the asker. *(`MatchService`.)*
- [ ] **P2.S18** — SwiftUI Ask screen: both ask types in one field, grouped examples, the four answer states of Figure A1. *(`AskView.swift`.)*
- [ ] **P2.S19** — Provider onboarding in SwiftUI: plain words in, editable tag chips out, radius and availability. *(`ProviderView.swift`, Inbox tab once a profile exists.)*
- [ ] **P2.S20** — *(Amendment, 2026-10-02.)* The answer is its own page: system back and a left-edge swipe return to Ask; a request still asking people survives going back and can be reopened or stopped. *(`AskView.swift`; UI walk swipes back from an offer and from a running request.)*
- [ ] **P2.S21** — *(Amendment, 2026-10-02, owner-authorized, built with Codex.)* Optional business profile on provider setup: name, description, one JPEG thumbnail (≤ 48 KiB, ≤ 512 px, re-encoded without metadata) and up to five `https://` links, opened only on a tap; shown on offers only through an explicit `provider_id`. *(`BusinessProfiles`, V7, contract 0.5.0 amendment.)*
- [ ] **P2.S22** — *(Amendment, 2026-10-02, owner decision, [ADR-011](../decisions/ADR-011-provider-described-skills.md).)* Vocabulary grows to 115 tags; a provider may keep up to five skills in their own words, and an ask naming no listed skill finds them by keywords (one-word skills need that word, longer ones two). Listed skills always win; the policy and the licence rule cannot be bypassed. *(`CustomSkills`, V8, own-skill chips in `ProviderView.swift`.)*
- [ ] **P2.S23–S26** — *(Amendments, 3–4 October 2026.)* Direct skill entry; the marketplace design and bottom navigation (ADR-012); admission-before-classification hardening and the no-coverage invitation; the full state walkthrough passing on a physical iPhone with the navigation fixes it exposed (`docs/testing/phase2-device-evidence-2026-10-04.md`).
- [ ] **P2.S27** — *(Amendment, 5 October 2026.)* Staff inspection read API for P2-TWO.S12: `GET /v1/admin/skills`, `/skills/gaps`, `/classifications`, `/refusals` — admin scope plus second factor, no-store, audited, no ask text or identities (`AdminInspection`, `AdminInspectionTest`). Automated accessibility audit of six main screens (`testAccessibilityAudit`, `evidence/P2/a11y/`). Contract 0.5.0 approved by the owner; frozen when Person Two approves and merges.
- [ ] **P2.S28** — *(Amendment, 5 October 2026.)* Asks in the person's own words: a clear service ask that names no listed skill and no provider's own words becomes a request labelled in those words (Claude's `service_label`, else the rules) and reaches providers by keywords; vague asks still get the one question (ADR-011 amendment, contract 0.6.0).
- [ ] **P2.S29** — *(Amendment, 5 October 2026.)* Staff accounts (ADR-013): invited by email, never added in code; email, password and an emailed six-digit code; owner and staff roles; disable ends every session. `StaffAccounts`, `StaffAccountsTest`, V9, `docs/runbooks/staff-accounts.md`, `node tools/staff.mjs`. Contract 0.6.0, approved by the owner; Person Two approves the pull request.

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
- [ ] Open-service test: any lawful service (e.g. shoe repair) maps onto vocabulary tags, and model output that fails validation or invents a tag falls back to the rules.
- [ ] Classification tests: service asks, place questions, unclear asks (one question) and refused asks, including private places.
- [ ] Provider tests: licence required, invented tag refused, same `user_id`, never matched to their own ask, `new` score never 0.

Verify with:

```bash
./backend/dev check contractTest
# With the isolated database variables from the runbook:
./backend/dev databaseTest
xcodebuild test -project ios/Plug.xcodeproj -scheme Plug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
# Capture real-device states using tools/run-phase2-device-evidence.sh and record
# the separate VoiceOver walkthrough before claiming the device gate has passed.
```

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
- [ ] A service with no participating supplier ends `no_coverage` honestly — never invented prices or availability.
- [ ] A place question nobody nearby can answer shows Unknown with real counts; a web answer, if any, is dashed and Not verified.
- [ ] A person can offer a service from the same account and sees the Inbox tab.
- [ ] The §16.8 design gate passes on every screen built in this phase.
- [ ] A provider failure degrades to the deterministic path without an error screen.
- [ ] `PROJECT_STATE.json` carries a signed `G2` entry.

---

## 7. Evidence to commit before the gate

Store everything under `evidence/P2/`:

- [ ] `ios/` — one screenshot per required state from the matrix in §12,
      on a real device, at default and largest Dynamic Type
- [ ] `failures/` — at least one deliberate failure, recovered, recorded
- [ ] `a11y/` — VoiceOver walkthrough of the primary flow
- [ ] `logs/` — the request ID from the connected checkpoint, in the backend log
- [ ] The correlation ID from the connected checkpoint, quoted in the tracker

---

## 7a. Design gate (§16.8)

Run on every screen built in this phase before G2. The 2026-10-02 run is recorded in
`docs/testing/phase2-v4-verification-2026-10-02.md`; the physical-device and greyscale
review by a second person is still required.

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
