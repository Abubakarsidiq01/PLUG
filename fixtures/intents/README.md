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
