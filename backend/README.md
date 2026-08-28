# Backend

Person One owns this Java 21 / Spring Boot 3 modular monolith. V1 deploys as one application while domain packages remain explicit boundaries.

## Run and test

```bash
gradle bootRun
gradle test
```

The service defaults to port `8080` and environment `local`. Override with `PLUG_ENVIRONMENT`.

## Package boundaries

- `foundation` — cross-cutting HTTP behavior and error envelopes
- `health` — readiness/health contract
- `request` — customer request intake

Future domains should be peers inside `com.plug`, not separate deployable services. PostgreSQL, Flyway, messaging, and external integrations are intentionally deferred until their phase requires them.
