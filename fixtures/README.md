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

## Phase 1 — auth (DRAFT 0.2.0, pending Person One approval)

Same rule: one file per outcome per operation. Each file is a copy of the matching
shape in `contracts/examples/`. Tokens and codes are placeholders, never real.

| Folder | Files |
|---|---|
| `auth.apple/` | `success`, `token-expired`, `token-replayed`, `invalid-token`, `link-conflict`, `consent-required`, `rate-limited` |
| `auth.phone.start/` | `success`, `validation-error`, `rate-limited` |
| `auth.phone.verify/` | `success`, `invalid-code`, `code-expired`, `too-many-attempts`, `link-conflict`, `rate-limited` |
| `auth.guest/` | `success`, `validation-error`, `rate-limited` |
| `auth.refresh/` | `success`, `token-expired`, `token-replayed`, `rate-limited` |
| `requests.create/guest-restricted.json` | 403 — a guest tried a member-only action |
