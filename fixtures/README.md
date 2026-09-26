# Fixtures

Deterministic inputs and responses, owned by Person Two (manual.docx §17.3). One
file per outcome per operation, named `<operation>/<outcome>.json`.

`contracts/examples/` holds the same shapes embedded next to the OpenAPI spec for
`ContractTest`; the files here are what the Bruno collection, Playwright and the
iOS decoding tests build against.

## requests.create

| File | Outcome |
|---|---|
| `success.json` | 202 — request accepted |
| `validation-error.json` | 400 — `validation_failed` |
| `auth-error.json` | 401 — `unauthenticated` |
| `rate-limited.json` | 429 — `rate_limited` |
| `transient-error.json` | 500 — `internal_error` |

## Phase 1 — identity and consent

Each file is the body the backend actually returns for that outcome, so a client test
built on it behaves like the real server. `FixtureContractTest` checks every file here
against `contracts/openapi.yaml`, and `FixtureBehaviourTest` / `UnavailableProviderTest`
compare the error fixtures with live backend responses. Tokens are placeholders.

| Folder | Files |
|---|---|
| `auth.apple/`, `auth.google/` | `success` (201), `invalid-token` (401), `unsupported-consent` (400), `link-conflict`, `account-exists`, `account-not-found` (409), `rate-limited` (429) |
| `auth.google/` | `unavailable` (503 — no Google client configured) |
| `auth.phone.start/` | `success` (202), `validation-error` (400), `rate-limited` (429), `unavailable` (503 — no SMS channel; offer another method or guest) |
| `auth.phone.verify/` | `success` (201), `invalid-code`, `code-expired`, `unsupported-consent` (400), `link-conflict`, `account-exists`, `account-not-found` (409), `rate-limited` (429 — also when attempts run out) |
| `auth.guest/` | `success` (201), `unsupported-consent` (400), `rate-limited` (429) |
| `auth.refresh/` | `success` (200), `session-ended` (401 — expired, revoked or replayed), `rate-limited` (429) |
| `auth.logout/` | `session-ended` (401); success is 204 with no body |
| `me.get/`, `me.consent/`, `me.sessions/` | `success`, plus `unauthenticated`, `unsupported-version`, `guest-forbidden` (403) and `not-found` (404) |

Auth routes take no `Idempotency-Key`: a retried sign-in creates a new session, and the
client keeps whichever one it received last.
