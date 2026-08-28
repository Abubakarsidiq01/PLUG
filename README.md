# PLUG

PLUG helps people find verified local services, live availability, pricing, and real-time answers through one request.

This repository is the V1 monorepo for two engineers. The backend is a Java 21 / Spring Boot 3 modular monolith, the iOS client is SwiftUI, and `contracts/openapi.yaml` is the shared API source of truth.

## Phase 0 goal

Phase 0 passes only when a physical iPhone calls the real staging backend, decodes `GET /health`, renders the response, and both engineers can find the correlated request in logs. A local-only demo is not the release gate.

## Repository map

- `backend/` — Person One; API, canonical state, data, integrations
- `infra/` — Person One; local and staging infrastructure
- `ios/` — Person Two; SwiftUI app, navigation, client behavior
- `contracts/` — shared; OpenAPI and reviewed examples
- `fixtures/` — shared; deterministic test inputs and responses
- `docs/` — shared; architecture, ADRs, runbooks, and testing evidence
- `.github/` — shared engineering workflow and CI

See [docs/OWNERSHIP.md](docs/OWNERSHIP.md) before changing shared contracts.

## First setup

1. Install Java 21, Gradle 8.10+, and Xcode 16+.
2. Run the backend with `cd backend && gradle bootRun`.
3. Verify `curl -i http://localhost:8080/health`.
4. Open `ios/Plug.xcodeproj` and run the `Plug` scheme.
5. Select the local environment in the app and confirm the API status renders.

Detailed instructions: [backend](backend/README.md), [iOS](ios/README.md), [contracts](contracts/README.md), and [onboarding](docs/runbooks/local-onboarding.md).

## Working agreement

- Branch from `main`; do not commit directly to it.
- Change `contracts/openapi.yaml` and examples before changing either implementation.
- Contract changes require both engineers' review.
- Use fixtures instead of private handwritten substitutes.
- Link test evidence and a correlation ID in integration PRs.
- Do not add Kafka, Kubernetes, microservices, or other V1 infrastructure without an accepted ADR.

## Current endpoints

- `GET /health` — reports service and environment.
- `POST /v1/requests` — validates and accepts a request stub.

## Useful commands

```bash
cd backend
gradle test
gradle bootRun
```

```bash
curl http://localhost:8080/health
curl -X POST http://localhost:8080/v1/requests \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: phase0-demo-1' \
  -d @../contracts/examples/request-create.json
```
