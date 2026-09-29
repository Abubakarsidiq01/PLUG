# Person Two — Windows local evidence, 2026-09-28

Person Two's own Windows 11 PC, on merged `main`. This closes the ADR-005 personal
setup follow-up (`P1-person-two-evidence`). It is local evidence only: it is not the
shared staging checkpoint and does not sign G1.

## Checkout and toolchain

| Item | Value |
|---|---|
| Commit | `3e8f96a12530c104f0ac25c4a463ee9995cceac9` (Merge PR #28) |
| OS | Windows 11 Home, 10.0.26200.9445 |
| Node | v22.13.0 |
| pnpm | 9.15.9 |
| Java | OpenJDK 21.0.12.1 (Temurin) |
| Docker | 29.8.0 (Docker Desktop, WSL2) — `infra-postgres-1` healthy |
| Bruno CLI | 4.1.0 (`tools/bruno`) |

## Web

```powershell
pnpm install --frozen-lockfile
pnpm --filter @plug/web lint
pnpm --filter @plug/web build      # from a clean web/.next
pnpm --filter @plug/web test:e2e
```

| Check | Result | File |
|---|---|---|
| Lint | passed, no findings | `web-lint-build.txt` |
| Production build | passed; `/`, `/admin`, `/admin/login`, `/privacy`, `/support`, `/terms` | `web-lint-build.txt` |
| Playwright (mobile 360, tablet 768, desktop 1280) | **69/69 passed** in one run, no retries (1.6 min) | `playwright.txt` |

Port 3000 was already in use by an older local `next` process, so the suite ran against
this build served with `next start` on port 3100 (`PLUG_WEB_URL=http://127.0.0.1:3100`),
which is the production-server mode CI uses.

## Local database and backend

```powershell
docker compose -f infra/compose.yml up -d --wait     # already running and healthy
.\gradlew.bat bootRun --args="--spring.profiles.active=db"
```

The backend received the configured database password and local-only
`PLUG_IDENTITY_PEPPER` in its environment (neither recorded here). The command
excerpt assumes those values were already exported: Spring Boot does not
automatically source a shell `.env.local` file. On start it applied `V2 identity` and
`V3 google identity` to the local database. `GET /health` and `GET /health/ready` both
answered `UP`, with database and migrations `UP` (`backend-startup.txt`).

## Bruno API collection

```powershell
npm ci --prefix tools/bruno --ignore-scripts --no-audit --no-fund
cd tests/api
..\..\tools\bruno\node_modules\.bin\bru.cmd run --env local -r
```

**PASS — 20/20 requests, 4/4 tests, 42/42 assertions** (`bruno-local.txt`). This covers
the Phase 0 health/request cases and the Phase 1 auth collection: guest sign-in, `/v1/me`,
guest restriction, admin refusal, refresh rotation and replay revocation, logout
revocation, anonymous access, an invalid Apple token, an unknown challenge and an unknown
consent version.

## Sanitisation

Before these files were added, the captured output and the backend log were searched for
access/refresh tokens, bearer headers, the database password and the pepper: none were
present. The Windows user path is replaced with `%USERPROFILE%` / `<user>`.

## Not covered here

- The joint staging/security checkpoint and external header capture (G1 step 8).
- Real SMS, Apple and physical-device evidence (Person One's steps).
- Approved legal text and the consent version (joint).
