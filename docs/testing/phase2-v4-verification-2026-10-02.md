# Phase 2 manual v4 — local verification, 2026-10-02

Person One, at the project owner's direction ("use the new production manual to design
Phase 2 entirely"). Scope: manual v4 Part V P2.S10–P2.S19 and the Person Two artefacts drafted
so neither lane waits ([ADR-010](../decisions/ADR-010-manual-v4-asks-skills-providers.md)).
Everything here ran on one Mac against disposable data. **It is not G2 evidence**: no second
person, no staging, no physical-device captures, contract 0.5.0 not yet approved.

## What ran

`tools/phase2-verify-all.sh`, in order, on a fresh disposable PostGIS and a fresh backend with
no `ANTHROPIC_API_KEY` (the built-in rules, so results are reproducible):

| Stage | Result |
|---|---|
| Backend unit, database, Checkstyle, boot JAR | Pass |
| Contracts, fixtures, labelled dataset (`pnpm test:contracts`) | 180 pass, 0 fail |
| Web typecheck and lint (site unchanged; see "Web" below) | Pass |
| OpenAPI lint, Spectral 6.15.0 at CI settings | No warnings or errors |
| Live API acceptance suite (`tools/phase2-live.mjs`) | 972 checks pass, 0 fail, 274 exchanges (`evidence/P2/security/phase2-live-2026-10-02.json`) |
| Bruno collection (`tests/phase2`) | 49/49 requests, 64/64 tests, 88/88 assertions |
| iOS unit tests plus live sign-in against the fresh backend | 63 tests, 0 failures |
| iOS simulator walks, default and largest Dynamic Type | Both walks pass; 30 screenshots |

New coverage added for v4:

- **Live suite**: an `asks()` section — service ask classified and tagged from the vocabulary,
  idempotent replay and key conflict, place question public with no invented answer and no
  promoted web answer, restricted ask and private place refused with 422, foreign and
  anonymous reads, one clarifying question then 409 on a second answer, provider propose
  (vocabulary-only tags plus unmatched terms), restricted skill description, licence
  required, invented tag refused, provider saved on the same account with a `new` score that
  is never 0. Provider calls now count against the shared per-address read budget.
- **Bruno**: requests 38–47 for the same cases; request 29 now expects `plumbing_minor`.
- **iOS unit**: every ask and provider fixture decodes and validates; a web answer labelled
  above Not verified is rejected; an asking place question polls without inventing an
  answer; `POST /v1/asks` carries the idempotency key; a 404 from `/v1/providers/me` is
  "not a provider", not an error.
- **iOS UI**: the walk covers offer a service, skills chips, provider setup, Inbox, the one
  question, offers, offer detail, stop asking, progress, no offers, restricted, place
  asking, place Unknown with the dashed web answer, and the saved-result error. 15 states
  × 2 text sizes in `evidence/P2/simulator/2026-10-02/`, with greyscale copies in
  `greyscale/`.

## Design gate (§16.8), iOS screens built in this phase

Run against the simulator captures and the source of `AskView.swift` and
`ProviderView.swift`. A second-person review on a physical device is still required.

| Check | Result |
|---|---|
| Every colour a token; no hand-typed hex | Pass (only `PlugTokens.Color.*`; `Color.clear` for the dashed badge) |
| No decorative truth colour | Pass (truth colours only inside `TruthBadge`) |
| Spacing on the 4/8/12/16/24/32/48 scale | Pass (`PlugTokens.Space` only) |
| Radius by role: 7 badges/chips, 9 controls, 12 cards, 20 sheets | Pass (system sheet) |
| No shadows | Pass |
| Primary button is ink | Pass |
| One family (system face on iOS) | Pass |
| Result headline is the value | Pass (price on offers, value on an answered place) |
| No tracked capitals above headings | Pass on iOS |
| No monospace as styling | Pass after fix: the reference lines were monospaced and are now caption style |
| One dominant task and one primary action per screen | Pass |
| Every required state screenshotted | Simulator only; physical device pending |
| No number the server did not send | Pass (counts, prices, times, distances, score all from responses) |
| Filled badge for people, dashed for the web, legible in greyscale | Pass in simulator greyscale copies; device check pending |
| Empty states say why and offer one action | Pass (No offers, No answers, Inbox) |
| Errors say what failed, whether anything was saved, what retry does | Pass |
| No placeholder copy, fabricated metrics or stock imagery | Pass |
| Button words match the state that follows | Pass (Ask → Asking…; Stop asking → You stopped asking) |
| No scroll or load animation; motion stops under Reduce Motion | Pass |
| No horizontal scroll; 44 pt targets | Pass (largest-text walk; chips and buttons ≥ 44 pt) |
| Contrast AA, computed | Pass: ink-900/paper 15.76, ink-600/paper 6.99, card/ink-900 17.58, alert-600/alert-50 5.16, confirmed 5.53, recent 4.97, estimated 5.07, unknown 4.96. ink-400 (3.44) is no longer used for text on these screens. |

Web: **fails** the gate. The committed site still uses the v3 layout through token aliases,
including tracked uppercase overlines. Manual §6.6 puts `/web` in Person Two's lane, so
Person One did not rebuild it; the partial draft is `docs/handoff/web-v4-retheme-draft.patch`.

## Fixes made during this run

- The place-question "asking" state never polled, and would have rendered as "No answers";
  `RequestModel` now polls it and `AskView` shows real counts while it is open.
- Six tabs pushed Profile into a More tab once Inbox appeared; the empty Phase 4 Contribute
  placeholder now gives way to Inbox.
- The simulator's fixed location keeps its original timestamp, and the app correctly rejects
  fixes older than two minutes; the evidence script now plays a slow route so every fix is
  fresh. A real phone is unaffected.
- The removed ADR-009 Apple Maps model and its imports are gone.

## Not proven here

- Physical-device screenshots, VoiceOver walkthrough and device greyscale review.
- Claude classification with a real key (none is configured; the rules ran).
- Person Two's Windows run, the contract session, the connected checkpoint, G2 signatures.
