# Phase 2 labelled intent dataset

`p2.jsonl` contains 46 synthetic test vectors for the proposed 0.4.0 contract (ADR-009: any lawful service).
One JSON object per line; no real prompts, accounts, tokens or private coordinates.
JSONL deliberately separates parser inputs from the response-body `.json` fixtures
that `FixtureContractTest` discovers.

Each vector includes a unique `id`, fixed `now`, `provider` condition, request
`input`, `schema_valid`, and partial `expected` outcome. `expected` states only the
fields relevant to that case. Omitted expected fields are not assertions of null.
`provider` values name the fault to inject into the future adapter test harness;
they are not extra API fields.

`pnpm test:contracts` checks dataset structure, required case coverage and the
request's JSON Schema validity. It does **not** run an intent extractor. Once the
contract is approved and Person One implements the adapter, run these vectors
against it with the injected clock and provider failure. A green static check
does not prove extraction, fallback, audit events, no outreach or rate limiting.

Some schema-valid requests must still fail service validation: whitespace/control
characters, non-USD currency, budget without currency, and out-of-window timestamps.
These distinctions are deliberate: the current proposal states these constraints
in prose. Do not treat `schema_valid: true` as authorization to accept the request.

The fixtures cover open services (barber, beauty, shoe repair, plumber, locksmith,
movers, restaurant), structured-field precedence, one service clarification,
prohibited requests, boundaries and deterministic fallback faults. Both engineers must review labels before freezing
the contract. The zone radius is not prescribed here; configure it on the server.

## Ask classification dataset

`asks.jsonl` contains 91 synthetic asks for `POST /v1/asks` (manual v4 §27.3, Person Two).
It is the answer key for the two-pipeline classifier: each row says what the server
should do with one sentence typed into the single ask field.

| `kind` | Rows | Expected |
|---|---|---|
| `service_request` | 38 | 201, `ask_type` `service_request`, at least one of `skill_tags_any_of`, none of `skill_tags_none_of` |
| `place_question` | 14 | 201, `ask_type` `place_question`, a public place named |
| `ambiguous` | 8 | 201, `ask_type` null, one clarification with field `ask` |
| `restricted` | 31 | 422 `restricted_intent`, no outreach, an audit event |

Each restricted row carries a `reason`: `illegal_goods_or_services`, `private_person`,
`disguised_surveillance` or `regulated_profession`. The reason is a label for people
reading the dataset. The API does not return it, so the live run cannot assert it.

Rows whose id starts with `near-miss-` are harmless asks that contain a word a refusal
rule might react to, such as "nail gun" or "kill the weeds". They must be accepted.
Rows starting `overlap-` name a skill whose phrase contains another skill's phrase, such
as "henna tattoo"; the specific skill must win. Rows starting `guide-` are the examples
printed in `docs/runbooks/phase2-asking-guide.md`, so the guide cannot drift from the build.
Licensed trades such as electrical work are service asks; the licence rule limits who
they are matched to, it does not refuse the ask.

Labels state what the manual requires, not what the current build returns. A row the
server disagrees with is a finding to raise, and the label changes only if both
engineers agree the label was wrong.

`pnpm test:contracts` checks the labels: unique ids, coverage of every kind and reason,
inputs valid against `AskBody`, and skills inside `contracts/skills.yaml`. To run the rows
against a disposable local backend with `requests_v2` on:

```powershell
$env:PHASE2_DISPOSABLE = "1"
$env:PHASE2_BASE_URL = "http://127.0.0.1:18083"
$env:PHASE2_REPORT = "$env:TEMP/asks-live.json"
node tests/contracts/asks-live.mjs
```

The run lists every row as `agrees` or `DIFFERS` and exits nonzero when any row differs.
Its report holds case ids, outcomes and correlation ids only.
