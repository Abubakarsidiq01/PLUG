# Phase 2 request acceptance

These tests target contract 0.3.0 with `plug.requests-v2.enabled=true`, identity and
PostGIS enabled. They do not accept the Phase 0 stub's 202 response. Keep the
existing `tests/api` collection for the default flag-off Phase 0/1 environment;
the Phase 2 collection is deliberately separate.

Use a **fresh disposable local database and backend**, seeded by its migrations,
with no SMS or model-provider credentials. Both suites create their own guest
accounts using consent version `2026-09-01`; no personal tokens are supplied.
Keep the original backend/database and identity pepper untouched. The synthetic
supplier zone is the fixture location; this is test data, not a live marketplace.
The runner refuses external origins and requires a disposable-runtime declaration.

From the repository root, after installing the locked dependencies:

```sh
pnpm install --frozen-lockfile
npm ci --prefix tools/bruno
node --check tools/phase2-live.mjs
pnpm test:contracts
PHASE2_DISPOSABLE=1 PHASE2_BASE_URL=http://127.0.0.1:18082 \
  PHASE2_REPORT=/tmp/phase2-live.json node tools/phase2-live.mjs
```

PowerShell equivalent for the live command:

```powershell
$env:PHASE2_DISPOSABLE = "1"
$env:PHASE2_BASE_URL = "http://127.0.0.1:18082"
$env:PHASE2_REPORT = "$env:TEMP/phase2-live.json"
node tools/phase2-live.mjs
if ($LASTEXITCODE -ne 0) { throw "Phase 2 acceptance failed" }
```

Run the portable Bruno collection against a fresh runtime, or wait at least 61
seconds after other request tests so previous quota consumption has expired:

```sh
cd tests/phase2
../../tools/bruno/node_modules/.bin/bru run --env local
```

On Windows, use `../../tools/bruno/node_modules/.bin/bru.cmd run --env local`.
Override with `--env-var baseUrl=http://127.0.0.1:PORT` when needed. Run the
collection in sequence; later requests depend on runtime-only variables set by
its guest/create/clarify steps. Its owner and other guest tokens are logged out
at the end. Never save token-bearing request/response reports or environment files.
The final disposable database teardown also removes unfinished test requests.

The Node runner validates each real response against OpenAPI plus the shared
semantic fixture assertions. It records case names, HTTP statuses, route templates
and correlation IDs, never tokens, request bodies, raw prompts, coordinates or
provider errors. Its JSON report is safe to review before copying into evidence.
Failure exits nonzero, including an unreachable backend, disabled v2, invalid JSON,
wrong status, schema mismatch or absence of seeded results. It never substitutes
fixture responses for live data. Functional dependencies stop after a failure;
a partial result has `passed: false` and cannot establish acceptance. A new run
first replaces any prior report with a `passed: false` running marker, so a killed
process cannot leave stale success evidence behind.

The live run takes several minutes because it observes actual one-minute rate
windows. It paces ordinary cases below both quotas, then deliberately tests ten
creations per account, thirty per caller address, and sixty resource-route calls
per address. Forwarding headers cannot manufacture a new trusted address.
No quota is disabled to produce a passing result.

| Coverage | Live collection / runner | Additional evidence required |
|---|---|---|
| Five request routes, owner-only access, malformed/missing IDs | Both; foreign identifiers produce 404 | Database ownership checks |
| Creation replay/conflict, clarification replay/conflict, no second question | Both; concurrent duplicate also in runner | Transaction/expiry tests |
| Real progress and seeded offers, budget/radius/deadline, honest labels | Runner waits for ranked and validates nonempty results | Worker/database tests |
| Cancellation, repeated cancellation, cancellation against active worker | Both; delayed worker check in runner | Row-lock race and terminal-state tests |
| Labelled extraction cases | All normal-provider rows from `fixtures/intents/p2.jsonl` run against HTTP | Injected provider faults run in backend tests |
| Unsupported/restricted requests | Both validate safe rejection | Audit record and no-outreach persistence assertions |
| Text, coordinates, budget, timestamp, unknown fields, coercion, duplicate JSON, body/media/header abuse | Runner; core cases also Bruno | Header/log redaction checks |
| Actual per-account/address/read rate limits | Runner, with Retry-After assertions | Multiple-process limit remains a release constraint |
| 403 stale consent / insufficient scope; deliberate 500 failure | Shared fixtures cover envelope; backend tests must provoke safely | Not claimed by ordinary guest HTTP runs |
| Figma, physical device, accessibility and two-person checkpoint | Outside this API suite | Separate review and evidence; G2 signatures |

Absolute timestamps in dataset inputs are shifted from each case's fixed `now`
to the live request's clock; expectations receive the same shift. This preserves
the meaning of past/future/boundary cases without changing the canonical parser.
Provider-fault labels are explicitly reported as backend-only tests: HTTP does
not expose a test-only switch that could affect production behavior.
