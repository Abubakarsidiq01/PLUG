# Supported Phase 2 request grammar

The backend `IntentAdapter`, request validators and OpenAPI contract are the
canonical implementation. Clients send the person's text and display the returned
constraints, question, status and `next_action`. QA must never add a second parser
in the app, web console or Bruno collection.

The local Phase 2 provider is deterministic and makes no external model calls.
Provider output, if a provider is subsequently injected, is untrusted: it must
validate before use and cannot supply offers, prices, truth labels or state.
Provider timeout, exception or invalid output falls back to deterministic extraction.
The provider deadline is six seconds and the executor is bounded; a provider that
ignores cancellation cannot grow an unbounded thread/queue backlog.

## Supported input

`text` and `location` are required. Text contains 1–500 characters, including at
least one non-whitespace character. Newlines are allowed; other control characters
are rejected. The complete HTTP body is capped at 16 KiB. Unknown fields, duplicate
JSON fields, wrong JSON types and explicit nulls in nonnullable input fields are
rejected rather than coerced.

Category recognition is case-insensitive and uses whole-word matches:

| Category | Recognised words/phrases |
|---|---|
| `barber` | `barber`, `haircut`, `hair cut`, `fresh cut`, `fade`, `beard`, `trim` |
| `beauty` | `beauty`, `manicure`, `pedicure`, `nail`, `nails`, `salon`, `lashes`, `makeup`, `braids` |

If no supported category is recognised, or both categories occur, the server
creates a `draft` with one structured category question. For example, “Something
nearby under $35” and “Need a fresh cut and my nails done” need that question.
Only the options on the issued question can be answered. Answering once removes
the question and submits the same request. Replaying the same answer/key is safe;
a different answer after submission, cancellation or expiry receives 409.

Money uses a dollar sign and a decimal amount, such as `$35`, `$35.50`,
`under $35`, `below $35`, `up to $35`, `max $35`, `maximum $35` or `budget of $35`.
The value is an upper limit in integer cents. Valid limits are $5–$500 inclusive;
USD is the only supported currency. Malformed money (`$35.999`, `$-5`, `$1,000`)
and conflicting multiple amounts are rejected. Repeating the same amount is allowed.
The client renders an omitted budget as
“Any price”, never an invented amount.

Relative deadlines use `in N minutes`, `in N mins`, `in N hours`, `in N hrs`,
or `in N days` (singular forms also work). `N` is an integer. The resulting
instant must be after the server's current time and at most seven days ahead.
Negative, zero, fractional or excessive durations and conflicting time clauses
are rejected; they do not silently become an unrestricted deadline.
“Barber under $35 in 30 minutes” therefore yields barber, 3500 cents and a
server-derived deadline thirty minutes ahead. No deadline means “As soon as
possible”. Phrases such as “tomorrow afternoon”, “by 4”, “half an hour” and
“next week” are outside the supported relative-time grammar; support should
use an explicit structured timestamp when a precise deadline is required.

Structured fields are authoritative over extraction of that same field:

| Field | Accepted values |
|---|---|
| `category` | `barber` or `beauty` |
| `budget_cents` | Integer 500–50000; `currency` required alongside it |
| `currency` | `USD` |
| `needed_by` | ISO-8601 timestamp with explicit offset; future and within seven days |
| `max_distance_m` | Integer 100–50000; defaults to 10000 |
| `location.latitude` / `longitude` | Finite JSON numbers in −90…90 / −180…180 |
| `location.precision` | `coarse` or `fine`; rounded by server to 3 / 4 decimal places |

An explicit valid category resolves otherwise ambiguous text. An explicit budget
or deadline overrides conflicting extraction for that field. No location question
is asked: the client must supply a location from the device or a geocoded address.
A response's timestamps use UTC, money uses cents and distance uses metres.

## Refusal and recovery

Recognised unsupported categories, including plumber, restaurant/dinner,
electrician, doctor, dentist, mechanic, taxi and pizza, receive 400
`validation_failed` with detail code `unsupported_category` when no explicit
supported category was supplied. They create no request or outreach. Unknown
wording does not silently select a category; it receives the single category
question. Explicit structured categories are still restricted to the allow-list.

Restricted intent receives 422 `restricted_intent`, creates no request/outreach
and records an audit event. The public response contains safe copy and the
correlation ID, without naming the policy rule or a created request identifier.
Do not interpret the existence of this deterministic filter as general semantic
policy coverage for arbitrary languages or adversarial paraphrases.

Malformed or out-of-range structured values receive 400. Oversized bodies receive
413; unsupported content type on create/clarification receives 415. Unauthenticated
requests receive 401; missing current consent or scope receives 403. Requests
belonging to another account, missing identifiers and malformed identifiers all
receive the same 404 shape. Rate-limited callers receive 429 with retry guidance.

The app follows `next_action` rather than guessing from time or offer-list length.
Progress counts refer to persisted synthetic supplier work in Phase 2. Synthetic
offers are labelled `estimated` or `unknown`, never `confirmed` or `recent`.
No outside supplier is contacted. Empty outcomes distinguish `no_coverage`,
`no_offers`, and `clarification_unanswered`.

The labelled dataset is `fixtures/intents/p2.jsonl`. Its normal-provider cases run
against the real local HTTP runtime; provider-failure variants and fixed-clock
edge cases also run in backend tests. See [the QA runbook](phase2-qa-runbook.md).
