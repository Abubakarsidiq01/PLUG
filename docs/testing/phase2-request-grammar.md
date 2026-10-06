# Supported Phase 2 request grammar

> Updated for ADR-009 (contract 0.4.0): any lawful service, Claude extraction, $5–$5,000.

The backend `IntentAdapter`, request validators and OpenAPI contract are the
canonical implementation. Clients send the person's text and display the returned
constraints, question, status and `next_action`. QA must never add a second parser
in the app, web console or Bruno collection.

When `ANTHROPIC_API_KEY` is set, the provider is Claude (`claude-sonnet-5-5`, low
effort, strict JSON schema). Without a key the rules below do all the extraction.
Provider output is untrusted: it must validate before use and cannot supply offers,
prices, truth labels or state. Stated money, times and distances parsed by the rules
win over the model; the model mainly names the service and its search terms.
Provider timeout, exception or invalid output falls back to deterministic extraction.
The provider deadline is six seconds and the executor is bounded; a provider that
ignores cancellation cannot grow an unbounded thread/queue backlog.

## Supported input

`text` and `location` are required. Text contains 1–500 characters, including at
least one non-whitespace character. Newlines are allowed; other control characters
are rejected. The complete HTTP body is capped at 16 KiB. Unknown fields, duplicate
JSON fields, wrong JSON types and explicit nulls in nonnullable input fields are
rejected rather than coerced.

Any lawful service is accepted. `category` is a snake_case identifier returned with a
display `service_name` and up to five `search_terms`. Claude names any service; the
rule-based fallback recognises (case-insensitive, whole words) barber, beauty, shoe
repair, plumber, electrician, auto repair, locksmith, house cleaning, tailor, phone
and computer repair, tutor, handyman, movers, laundry, car wash, pet grooming,
veterinarian, dentist, doctor, pharmacy, massage, photographer, towing and restaurant
(`IntentAdapter.SERVICES` is canonical). Barber and beauty are the only services with
seeded participating suppliers; every other service ends `no_coverage`, and the app
then lists real nearby businesses from Apple Maps with price and availability Unknown.

If no service is recognised, or more than one is, the server creates a `draft` with one
structured service question (the matched services, Claude's candidates, or eight
popular services). For example, “Something
nearby under $35” and “Need a fresh cut and my nails done” need that question.
Only the options on the issued question can be answered. Answering once removes
the question and submits the same request. Replaying the same answer/key is safe;
a different answer after submission, cancellation or expiry receives 409.

Money uses a dollar sign or the word dollars/bucks/USD, such as `$35`, `$35.50`,
`$1,200`, `45 dollars` or `under $35`.
The value is an upper limit in integer cents. Valid limits are $5–$5,000 inclusive;
USD is the only supported currency. Malformed money (`$35.999`, `$-5`, `$1,00`)
and conflicting multiple amounts are rejected. Repeating the same amount is allowed.
The client renders an omitted budget as
“Any price”, never an invented amount.

Relative deadlines use `in N minutes`, `in N mins`, `in N hours`, `in N hrs`,
or `in N days` (singular forms also work). `N` is an integer. The resulting
instant must be after the server's current time and at most seven days ahead.
`today`, `tonight` and `tomorrow` (optionally `morning`, `afternoon`, `evening`, `night`)
are read in the person's `time_zone`: a bare day means 23:59 that day, morning 12:00,
afternoon 17:00, evening/night 21:00. `within N miles|km` sets the search radius.
Negative, zero, fractional or excessive durations and conflicting time clauses
are rejected; they do not silently become an unrestricted deadline.
“Barber under $35 in 30 minutes” therefore yields barber, 3500 cents and a
server-derived deadline thirty minutes ahead. No deadline means “As soon as
possible”. Phrases such as “tomorrow afternoon”, “by 4”, “half an hour” and
“next week” are outside the rule-based grammar (Claude may still read them); support should
use an explicit structured timestamp when a precise deadline is required.

Structured fields are authoritative over extraction of that same field:

| Field | Accepted values |
|---|---|
| `category` | snake_case service identifier, 2–40 characters |
| `budget_cents` | Integer 500–500000; `currency` required alongside it |
| `time_zone` | IANA zone such as `America/Chicago`; defaults to UTC |
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

There is no unsupported-category refusal (ADR-009). A service with no participating
supplier is created and ends `expired` / `no_coverage` without outreach. Unknown
wording does not silently select a service; it receives the single service question.

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
