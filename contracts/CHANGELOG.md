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

### 0.3.0 — 2026-10-01 — BREAKING (POST /v1/requests only) — P2.S1
Freezes the Phase 2 request contract (manual.docx §18.3, §19.5, §19.6, §27.3).
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
Fixtures: Person Two writes `fixtures/requests.{create,get,clarify,offers,cancel}/` in the
P2.S1 fixture pull request (§7.2). `FixtureContractTest` already maps those folders and
holds the old `requests.create/success.json` to the deprecated stub schema until then.
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
