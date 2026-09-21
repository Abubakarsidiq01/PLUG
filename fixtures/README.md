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
