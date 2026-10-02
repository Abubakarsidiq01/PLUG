# Contract changelog

Every change to `/contracts` gets an entry. Both approvals required on the pull
request. Format:

```
### <version> — <date> — additive | BREAKING — <state token>
<what changed, in one or two sentences>
Fixtures updated: <paths>
Migration note: <none | what must happen, in what order>
Rollback: <what turning the flag off does>
```

### 0.5.0 amendment — 2026-10-02 — additive — proposed — optional business profiles
Owner-authorized (implemented with Codex, completed by Person One). A provider may add
optional public details: `BusinessProfile` (`name` ≤80, `about` ≤300, `photo_base64` a JPEG
of at most 48 KiB decoded and 512×512, re-encoded server-side so EXIF/GPS is dropped, and
up to five `BusinessLink`s of `label` plus a public `https://` URL with no credentials,
no IP or `.local` host). `ProviderSetup.business`: omitted keeps the stored details, `{}`
removes them. `ProviderProfile.business` and `ServiceOffer.business` return them; an offer
carries them only through an explicit `provider_id`, never by matching a name or place.
Nothing is fetched server-side and links open only on a customer tap. `POST
/v1/providers/skills` accepts up to 96 KiB for the thumbnail; every other route keeps 16 KiB.
`ServiceOffer.provider_score` now reflects the provider's real completed jobs and trust.
Fixtures updated: `fixtures/requests.offers/business-profile.json`, `fixtures/asks.get/answered.json`
(answered place question with source initials); manifest regenerated.
Migration note: `V7__optional_business_profiles.sql` adds `provider_profiles.business`
(JSONB, default `{}`, ≤75 000 bytes) and nullable `request_offers.provider_id`. Expand-only.
Rollback: `requests_v2` off removes the routes; the columns are inert without them.

### 0.5.0 — 2026-10-02 — BREAKING vs proposed 0.4.0 (unmerged) — proposed — manual v4 / ADR-010
Manual v4 Part V (P2.S10–P2.S17). One ask field serves two kinds of ask: `POST /v1/asks`
classifies into `service_request` or `place_question` and returns `AskResult` (exactly one of
`request`, `place_question`, or a single `clarification` with `field: ask`), with
`GET /v1/asks/{ask_id}` and `POST /v1/asks/{ask_id}/clarifications`. Skills come only from
the new controlled vocabulary `contracts/skills.yaml` (35 tags, owned by Person Two, changed
by pull request plus migration): `RequestConstraints.search_terms` is removed and replaced by
required `skill_tags` (vocabulary tags) and `licence_required`. Any lawful service is in
scope; the restricted-intent policy is now the only refusal path and runs before any model
call (refusals are audited; place questions about a private place are refused the same way).
Provider capability is added to the caller's existing account: `POST
/v1/providers/skills/propose`, `POST /v1/providers/skills`, `GET /v1/providers/me` (404 until
the caller offers a service); a `requires_licence` tag needs `licence_ref`
(`details[].code` `licence_required`) and an invented tag is refused (`unknown_skill`).
`ServiceOffer` gains required `provider_score` (`new` below three completed jobs, never 0).
`TruthLabel` gains `not_verified`, reserved for `WebAnswer`, which can never carry a human
label. The Apple Maps listing from ADR-009 is withdrawn. `POST /v1/asks` shares the creation
rate budget with `POST /v1/requests`. Error codes and auth@0.2.2 are unchanged.
Fixtures updated: new `fixtures/asks.create|asks.get|asks.clarify|providers.propose|
providers.skills|providers.me` (captured from the real backend, errors from templates);
every `fixtures/requests.*` resource and `contracts/examples/requests-*` migrated from
`search_terms` to `skill_tags`/`licence_required`/`provider_score`; `fixtures/intents/p2.jsonl`
46 vectors re-labelled against the vocabulary; manifest at 117 rows.
Migration note: `V6__asks_skills_providers.sql` adds `skill_vocabulary` (seeded from
skills.yaml; the backend refuses to start if the two disagree), `asks`, `place_questions`,
`provider_profiles`, `provider_skills`, `provider_availability`, `provider_scores`,
`request_matches` and `vocabulary_gaps`. Expand-only. Backend first, then the iOS build.
Rollback: `requests_v2` off removes every route above; the Phase 0 stub stays.

### 0.4.0 — 2026-10-01 — BREAKING vs proposed 0.3.0 (unmerged) — ADR-009
Owner decision: PLUG serves any lawful service, not only barber and beauty. `Category`
becomes a snake_case identifier (`^[a-z][a-z0-9_]{1,39}$`) instead of the enum
`[barber, beauty]`; `RequestConstraints` gains required `service_name` (null exactly when
category is null) and `search_terms` (0–5 phrases, empty exactly when category is null);
`CreateRequestBody` gains optional `time_zone` (IANA) so "tomorrow" is the person's day;
budget limits widen to 500–500000 cents ($5–$5,000). The `unsupported_category` refusal
is removed: a service no participating supplier covers is created and ends `expired` /
`no_coverage`, and the iOS app may list real nearby businesses from Apple Maps with price
and availability shown as Unknown. Clarification options are chosen per request. Error
codes, routes, status/next_action enums and auth@0.2.2 are unchanged.
Fixtures updated: every `fixtures/requests.*` resource and `contracts/examples/requests-*`
gains `service_name`/`search_terms`; `requests.create/unsupported-category.json` and
`requests-unsupported-category-error.json` removed; `requests-create-open-service.json`
added; `fixtures/intents/p2.jsonl` now 46 vectors (open services, $1,200, over-cap).
Migration note: `V5__open_service_scope.sql` is expand-only (relaxed checks, new nullable
columns, backfill of V4 barber/beauty rows). Backend first, then the iOS build.
Rollback: `requests_v2` off; V5 leaves V4 data valid.

### 0.3.0 — 2026-10-01 — BREAKING (POST /v1/requests only) — P2.S1
Proposes the Phase 2 request contract (manual.docx §18.3, §19.5, §19.6, §27.3).
Still awaiting both engineers' approval and merge; it is not frozen or implemented.
Person Two hardening: an unanswered draft keeps its null category when canceled or
expired with clarification_unanswered, rather than inventing a category to close it.
Restricted errors omit a created resource ID but retain error.request_id for correlation.
Fixtures now cover every documented HTTP response across all five operations, plus
draft cancellation/expiry, ownership denial, and the labelled intent cases. See
`tests/contracts/fixture-manifest.json` and `fixtures/intents/p2.jsonl`.
`POST /v1/requests` is replaced: body `CreateRequestBody` (`text` ≤ 500 plus optional
`category`, `budget_cents`/`currency`, `needed_by`, `max_distance_m`, and `location`
with `precision`), required `Idempotency-Key` (16–128), `plugSession` auth instead of
`stagingJwt`, 201 `RequestResource` instead of 202, and new 409 / 422 responses. Adds
`GET /v1/requests/{request_id}`, `POST /v1/requests/{request_id}/clarifications`,
`GET /v1/requests/{request_id}/offers` and `POST /v1/requests/{request_id}/cancel`.
Adds the `RequestStatus` (11 values, §19.6 transitions plus `draft -> expired`) and
`NextAction` (7 values) enums with a one-to-one status mapping, `RequestProgress`,
`Clarification` (category only, at most one per request), `NoResultReason`, `Offer`,
`Place`, `TruthLabel` and `OfferSource`. Money is integer cents plus ISO 4217 (USD only
in V1); time is ISO-8601 with an explicit offset, emitted in UTC. The error-code enum
is unchanged: new outcomes are `details[].code` tokens — `unsupported_category`,
`in_the_past`, `too_far_ahead`, `not_an_option`, `consent_required`,
`idempotency_key_reused`, `request_in_progress`, `not_awaiting_clarification`,
`not_cancelable`. All identity routes (auth@0.2.2) are unchanged.
The Phase 0 stub schemas are renamed `Phase0RequestCreate`, `Phase0Location` and
`Phase0RequestResponse`, marked deprecated, and kept only so the stub the backend still
serves stays tested; they are removed in the implementation pull request.
Examples: `contracts/examples/requests-*.json` — one per documented outcome.
Fixtures: `fixtures/requests.{create,get,clarify,offers,cancel}/` now use the proposed
0.3.0 shapes (§7.2). The old stub remains covered by `request-response.json` and the
explicit Phase 0 Bruno requests until backend implementation. `FixtureContractTest`
validates the new response bodies; `pnpm test:contracts` additionally checks status
coverage, cross-field invariants and the labelled dataset's input schema expectations.
Tests: `ContractTest` validates every new example and checks the status → next_action
mapping, the present-if-and-only-if fields and the progress invariants across them.
Migration note: no database change in this pull request. The backend ships the new routes
behind flag `requests_v2` (default off) with the P2.S3/S4 migrations; iOS adopts them in
P2.S9. Neither app calls `POST /v1/requests` today. The only consumers are the two
Bruno requests in `tests/api/requests-create-*.bru`, which target the stub and are
rewritten in Person Two's P2.S2.
Rollback: revert this pull request; nothing depends on it until `requests_v2` exists.
With the flag off, the Phase 0 stub keeps its 0.1.0 behaviour.

### 0.2.2 — 2026-09-28 — metadata reconciliation — approved implementation
Align OpenAPI info.version with the existing 0.2.2 signup/signin-intent entry.
No endpoint, schema, runtime behavior or fixture content changes. The implementation
and fixtures were approved through PRs #25/#27 and reached main through #28.
Person One authorized the completion record on 2026-09-28. This contract record
is not the separate G1 device/staging sign-off.
Migration note: none. Rollback: metadata-only revert.

### Unreleased — 2026-09-26 — fixtures and examples only — P1.S1
No route or schema change. Replaces the unimplemented 0.2.0 draft shapes (guest
`device_id`, nested terms/privacy consent, flat session fields, `chl_` challenges,
relative expiry, JWT access tokens and the auth `Idempotency-Key` replay promise) with
examples and fixtures that match the implemented contract: opaque tokens, 201 on
sign-in, `consent_version`, `cha_` challenges, absolute expiry, the 30-day verified /
7-day guest refresh policy (ADR-006), Google sign-in, `sign_up`/`sign_in` intent with
`account_exists`/`account_not_found`, and `503 dependency_unavailable` when phone
delivery or Google is not configured. Only `POST /v1/requests` accepts
`Idempotency-Key`; auth routes do not replay, and `FixtureContractTest` keeps it so.
Validation `details[].field` now uses the snake_case wire name (`phone_number`, not
`phoneNumber`), matching the request body and the fields `ApiException` already used.
Fixtures updated: `fixtures/auth.{apple,google,guest,phone.start,phone.verify,refresh,logout}/*`,
`fixtures/me.{get,consent,sessions}/*`; removed `fixtures/requests.create/guest-restricted.json`
(guests are not restricted on that route).
Tests: `FixtureContractTest` validates every fixture and example against its schema;
`FixtureBehaviourTest` and `UnavailableProviderTest` send the examples to the real
backend and compare status, code, details and message with the fixture.
Migration note: none. Rollback: revert the commit; no server state depends on it.

### 0.2.2 — 2026-09-25 — additive — draft, not jointly frozen
Apple/Google authentication and phone verification accept optional `intent`:
`sign_up` rejects an existing verified identity; `sign_in` rejects an unknown one.
Both return HTTP 409 with `error.code=conflict` and an `intent` detail containing
`account_exists` or `account_not_found`. Checks run after ownership verification.
Omitting intent preserves the earlier combined flow. Identity matching uses the
provider's verified subject, not an unverified or cross-provider email address.
Fixtures/tests: GoogleSignInTest, AuthenticationModelTests.
Migration note: no database migration; deploy backend before the updated client.
Rollback: revert clients first; earlier servers reject the new request field.

### 0.2.1 — 2026-09-24 — draft, not jointly frozen
User-requested expansion: Google sign-in (`POST /v1/auth/google`) and the `google`
account type; real SMS through explicitly configured Twilio delivery. Google checks
signature, issuer, server client audience, expiry, nonce and single use. Existing
phone verification creates or returns an account after OTP verification, without
revealing whether a number is registered. No passwords are stored; recovery is
specific to the chosen provider.
Fixtures/tests: GoogleSignInTest and TwilioPhoneCodeSenderTest.
Migration: apply V3 before enabling Google. Ship clients accepting the new account type
before enabling the provider. No changes to already-applied migrations.
Rollback: clear Google client configuration and select `phone-delivery=none`;
existing Google sessions remain readable. Keep V3 applied.

### 0.2.0 — unreleased — P1.S1
Additive. Adds the identity and consent surface: `POST /v1/auth/apple`,
`POST /v1/auth/phone/start`, `POST /v1/auth/phone/verify`, `POST /v1/auth/guest`,
`POST /v1/auth/refresh`, `POST /v1/auth/logout`, `GET /v1/me`,
`POST /v1/me/consent`, `GET /v1/me/sessions` and
`GET`/`DELETE /v1/me/sessions/{session_id}`; the `plugSession` bearer scheme; and the
`Conflict`, `NotFound` and `DependencyUnavailable` responses. The error-code enum is
unchanged — a wrong or expired one-time code is a `validation_failed` whose
`details[0].code` is `invalid` or `expired`, and a spent attempt budget is `rate_limited`.
Access tokens live 15 minutes. Refresh tokens rotate on every use and live 30 days for a
verified account, 7 days for a guest; replaying a rotated token revokes the whole chain.
No Phase 0 operation changed.
Fixtures: `contracts/examples/{session,phone-challenge,me,invalid-code-error,account-link-conflict-error}.json`
Migration note: `V2__identity.sql` creates `users`, `identities`, `sessions`,
`consents`, `phone_challenges`, `apple_token_uses` and `audit_events`. It runs before
the code that reads them, and it adds no column to an existing table.
Rollback: set `plug.identity.enabled=false`. The auth routes stop being registered and
Phase 0 behaviour is unchanged; no migration has to be reversed.

### 0.1.0 — unreleased — P0
Initial contract: `GET /health`, `GET /health/ready`, `POST /v1/requests` stub,
and the shared error envelope.
Fixtures: `fixtures/requests.create/{success,validation-error}.json`
Migration note: none.
