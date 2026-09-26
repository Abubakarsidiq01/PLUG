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
