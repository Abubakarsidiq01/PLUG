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
