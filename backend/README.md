# Backend

Person One owns this Java 21 / Spring Boot 3 modular monolith. V1 deploys as one application while domain packages remain explicit boundaries.

## Run and test

```bash
./dev bootRun
./dev test
./dev check bootJar
```

The service defaults to port `8080` and environment `local`. Override with `PLUG_ENVIRONMENT`.

`./dev` selects the Java 21 installation in `../.tools` if `JAVA_HOME` is unset, and keeps Gradle downloads/cache inside the project. On another machine, install Java 21 and set `JAVA_HOME`, then use the same commands. The Gradle wrapper pins version 8.14.3.

Stop the foreground server with Ctrl+C. The request endpoint is a Phase 0 stub: it does not persist requests, contact suppliers, or process idempotency keys. Do not expose it publicly as a production service.

Responses include an `X-Correlation-ID` header. Backend request logs include that same ID. Validation error bodies use it too.

## Package boundaries

- `foundation` — cross-cutting HTTP behavior and error envelopes
- `health` — readiness/health contract
- `request` — customer request intake

Future domains should be peers inside `com.plug`, not separate deployable services. PostgreSQL/PostGIS and Flyway are enabled with the `db` or `staging` profile. Supplier messaging and other product integrations remain out of Phase 0.

## Database and staging checks

Start local PostgreSQL/PostGIS using `infra/compose.yml`, export `PLUG_DATABASE_PASSWORD`, and run `./dev databaseTest`. This check fails if the database is missing; it is not silently skipped.

Staging must activate the `staging` profile and provide an HTTPS JWT issuer, audience, and separate runtime/migration database credentials. See `docs/runbooks/staging-deployment.md`. The runtime role must not own the database.

Local requests are limited to 60 per minute per peer, 16 KiB per body, and 1000 query characters. Unknown/duplicate fields, trailing JSON, and string coordinates are rejected. Pool, queue, and connection limits are starting bounds, not proven throughput targets. Tune them only after representative load tests.

## Phase 2 request flow

Enable `PLUG_REQUESTS_V2_ENABLED=true` with the `db` or `staging` profile and identity
configuration. It defaults to false, preserving the Phase 0 stub for rollback.
The five `/v1/requests` routes then require a PLUG guest or member session. Creation
also requires current consent. Creation and clarification require a stable
`Idempotency-Key` containing 16–128 ASCII letters, digits, underscores or hyphens.

Flyway V4 adds requests, constraints, PostGIS places, synthetic supplier schedules,
seed work, offers and durable idempotency responses. The seed demo zone is centered
at latitude `32.528`, longitude `-92.714`. The synthetic barber schedules offer
$30/$35 slots 20/25 minutes after creation; beauty offers a $35 slot after 20 minutes.
These are demo listings, always labeled `estimated` and `source: seed`, with no
supplier messages, reservation, or confirmation. Outside the demo zone the server
returns an honest no-coverage result. A one-second worker performs bounded work
under database row locks and resumes unfinished work after restart. Polling reads
persisted progress; no timer manufactures counts or regenerates offer times.

The default intent provider uses deterministic extraction without external calls or
model costs. An injectable provider is schema/range checked and has a six-second
caller deadline; failure falls back to the same deterministic path. Provider output
cannot produce offers or state transitions. Supported words include barber, haircut,
fade, beard and trim; beauty, manicure, pedicure, nails, salon, lashes, makeup and
braids. Dollar amounts and `in N minutes/hours/days` extract constraints. Conflicting
or malformed recognized amounts/times fail validation; explicit structured values
are authoritative. Missing or ambiguous category asks exactly one structured question.

Run `./dev check contractTest bootJar` for unit, style and contract verification.
Run `./dev databaseTest` only against a disposable PostGIS database: inherited
identity tests intentionally truncate identity tables. Phase 2 integration tests
exercise the 42 labelled cases, ownership, real migrations, replay, progress,
expiry, no-result states, restrictions and concurrent cancellation. Do not run
this test task against an account database used by a person.
