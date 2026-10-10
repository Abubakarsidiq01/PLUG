# Fixtures

Deterministic inputs and responses, owned by Person Two (manual.docx §17.3). One
file per outcome per operation, named `<operation>/<outcome>.json`.

`contracts/examples/` holds the same shapes embedded next to the OpenAPI spec for
`ContractTest`; the files here are what the Bruno collection, Playwright and the
iOS decoding tests build against.

## Phase 3 — proposed contract 0.7.0

One scenario runs through every Phase 3 file: the ranked barber request
`req_01J9Z6Q3V8M2K4P7R5T1W0XY3B` from `requests.get/success.json` gets an SMS offer from
Fade Factory Barbers and an in-app offer from a new provider; the asker selects the SMS one
(`requests.select/success.json`), which is confirmed (`requests.get/confirmed.json`),
released (`requests.get/reservation-released.json`, alternate-offer recovery) or lapses
(`requests.get/not-confirmed.json`).

| Folder | Covers |
|---|---|
| `requests.select/` | selection, replay, `already_selected`, `offer_unavailable`, `not_selectable` |
| `requests.send-offer/` | a matched provider's offer; `over_budget`, `outside_window`, `contact_in_note`, `already_offered`, `request_closed`, never matched (404), suspended (403) |
| `providers.inbox/`, `providers.decline/`, `providers.reservation/` | the inbox, a free decline, confirm and release |
| `suppliers.opt-in/` | the one public route: the same 202 for every number, consent and version errors |
| `admin.suppliers.*`, `admin.messages/`, `admin.opt-outs/`, `admin.matches/`, `admin.providers.*` | the admin monitor and management routes; every number masked |

`contracts/messages/cases.v1.json` holds the SMS reply cases; they are the parser's
regression fixtures and live next to the copy because the two change together.

## Phase 2 — proposed request contract 0.3.0

`requests.create/`, `requests.get/`, `requests.clarify/`, `requests.offers/` and
`requests.cancel/` contain 68 deterministic response bodies. These are review
fixtures, not evidence that Phase 2 endpoints are live. The current backend still
serves the Phase 0 stub (202 / RECEIVED); its example and Bruno checks remain separate.

Run `pnpm test:contracts` from the repository root after `pnpm install --frozen-lockfile`.
This uses the OpenAPI schemas directly, validates date-time formats and checks the
prose invariants, HTTP/error mapping, coverage, and preservation of a draft's identity.
The backend's `./dev test --tests '*FixtureContractTest'` also checks response schemas.

`tests/contracts/fixture-manifest.json` maps every file to its method, route, status,
and source example when copied verbatim. Every documented response is represented;
there are no invented 400s for bodyless routes. Empty results are represented by
`requests.get/empty.json` and `requests.offers/empty.json`. Creation, clarification
and cancellation return resources, so an empty body is not a valid success there.

Additional cases cover missing/malformed/other-owner IDs (identical 404 envelopes),
idempotency conflicts, expiration, unanswered draft cancellation, all three no-result
reasons, unknown labels, and offers still pending. Seed supplier names and addresses
are synthetic examples from the contract, never proof of live businesses or replies.
Dates are evaluated against the manifest's fixed clock, never the machine's date.

The labelled intent dataset is `intents/p2.jsonl`; its format and verification limits
are documented in [intents/README.md](intents/README.md).

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
