# PLUG

PLUG helps people find verified local services, live availability, pricing, and real-time answers through one request.

This repository is the V1 monorepo for two engineers. The backend is a Java 21 / Spring Boot 3 modular monolith, the iOS client is SwiftUI, `web/` is the Next.js public site and admin console, and `contracts/openapi.yaml` is the shared API source of truth.

**Read `PROJECT_STATE.json` first.** It says which phase the project is in, who owns the next step, and what must not be touched.

## Start here

| You are | Open |
|---|---|
| Person One, new to the repo | `docs/onboarding/mac.md` |
| Person Two, new to the repo | `docs/onboarding/windows.md` |
| Resuming work | `PROJECT_STATE.json`, then the file in its `readme` field |
| Any contributor | `docs/CONTRIBUTOR_WORKFLOW.md` |

## Phase 0 goal

Phase 0 passes only when a physical iPhone calls the real staging backend, decodes `GET /health`, renders the response, and both engineers can find the correlated request in logs. A local-only demo is not the release gate.

## Repository map

- `backend/` — Person One; API, canonical state, data, integrations
- `ios/` — Person One; SwiftUI app, navigation, client behavior (macOS-only, manual.docx §5)
- `infra/` — Person One; local and staging infrastructure
- `db/migrations` — Person One; Flyway migrations, applied from `backend/src/main/resources/db/migration` (Spring Boot's default classpath location — the top-level `db/` directory in the manual's tree diagram is the same migrations, not a duplicate set)
- `web/` — Person Two; Next.js public site + admin console
- `tests/` — Person Two; Bruno API collections and Playwright E2E
- `fixtures/` — Person Two; one deterministic file per outcome per operation
- `design/` — Person Two; design tokens and the CSS/Swift generator
- `contracts/` — shared; OpenAPI, examples, message templates and CHANGELOG.md
- `docs/` — shared; the phase READMEs, onboarding, security, runbooks and ADRs
- `evidence/` — shared; screenshots, traces and recordings per gate
- `.github/` — shared engineering workflow and CI

See [docs/OWNERSHIP.md](docs/OWNERSHIP.md) and `.github/CODEOWNERS` before changing another lane's path.

## First setup

1. Install Java 21. Gradle 9.7.1 is managed by the checked-in wrapper; a separate Gradle installation is not needed. Xcode 16+ is needed only for iOS work.
2. Run the backend with `cd backend && ./dev bootRun` (the helper uses project-local Java when installed).
3. Verify `curl -i http://localhost:8080/health` and `curl -i http://localhost:8080/health/ready`.
4. Open `ios/Plug.xcodeproj` and run the `Plug` scheme.
5. Open the Engineering tab and confirm the API status renders. Debug builds default to the local backend; set `PLUG_API_URL` in the scheme for staging.

Backend hardening and verification: `cd backend && ./dev check bootJar`. Real database checks: `./dev databaseTest` after starting PostgreSQL/PostGIS.

Detailed instructions: [backend](backend/README.md), [iOS](ios/README.md), [contracts](contracts/README.md), [Mac onboarding](docs/onboarding/mac.md), [Windows onboarding](docs/onboarding/windows.md).

## Working agreement

- Branch from `main`; do not commit directly to it. Branch names follow `<phase>.<step>-<lane>-<short-name>`.
- Change `contracts/openapi.yaml` and examples before changing either implementation.
- Contract changes require both engineers' review.
- Use fixtures instead of private handwritten substitutes.
- Link test evidence and a request ID in integration PRs.
- Update `PROJECT_STATE.json` in the same pull request as the work it describes.
- Do not add Kafka, Kubernetes, microservices, or other V1 infrastructure without an accepted ADR.

## Current endpoints

- `GET /health` — liveness only: status, version, commit. No environment name, no configuration.
- `GET /health/ready` — readiness: database and migration status. Kept off the public internet at the infra layer.
- `POST /v1/requests` — validates and accepts a request stub.

## Useful commands

```bash
cd backend
./dev test
./dev bootRun
```

```bash
curl http://localhost:8080/health
curl http://localhost:8080/health/ready
curl -X POST http://localhost:8080/v1/requests \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: phase0-demo-1' \
  -d @../contracts/examples/request-create.json
```
