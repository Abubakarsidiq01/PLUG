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
