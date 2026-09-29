# Person Two — Phase 1 setup record

Recorded by Person Two (`@uzom-a`) on 2026-09-21, following
[person-two-phase1-handoff.md](person-two-phase1-handoff.md) on her own
Windows 11 computer.

- **Checkout:** merged `main` at `938d5f3fabc0031df64781761f73bc131d8da580`
  (PR #10).
- **Toolchain:** Git, Node, GitHub CLI, Docker Desktop 29.8.0 and WSL2 (Ubuntu,
  version 2) were already present. pnpm 9.15.9, Bruno CLI 4.1.0 and Temurin JDK
  21.0.12 were installed during this session. Person One subsequently supplied
  her Node version: **v22.13.0**, installed at
  `C:\Program Files\nodejs\node.exe` (operator-reported).
- **Web browser tests (operator-reported):** two desktop accessibility cases
  (`public-shell`, `admin-login`) timed out on the first cold run; a targeted
  accessibility rerun passed 6 of 6. The original report also stated 21/21, but
  did not establish whether that was a separate complete run. This was resolved
  in PR #23 (commit `fc7d235`): Person Two reports a clean `.next` cache, no prior
  server, and 21/21 passing in one run with no retries after bounding the slow
  accessibility test appropriately. Local lint and production build also passed.
- **Backend:** `docker compose -f infra/compose.yml up -d --wait` started a
  healthy Postgres; `bootRun` with the `db` profile started in about 6 s and
  `/actuator/health` returned 200.
- **Bruno:** `bru run --env local` from `tests/api` passed 4 of 4 requests and
  11 of 11 assertions.

## Setup corrections

1. Open a new terminal after `winget` installs; Java is not on PATH otherwise.
2. The first `docker compose up` failed to pull the Postgres image with a TLS
   error and succeeded on retry (documented in `windows.md`).
3. There is no standing staging URL (ADR-004). Supply a fresh tunnel URL
   explicitly when repeating a public checkpoint; do not reuse a saved hostname.
4. `fixtures/README.md` omitted `rate-limited.json`.

These are Person Two's reported results on the recorded checkout. Sanitized
local logs/reports have not yet been attached to this record. They do not prove
the later dependency revision.

## Completed public checkpoint — 2026-09-22

The public API run from Person Two's Windows PC was completed in the joint
session recorded in [the connected checkpoint log](../../evidence/P0/logs/connected-checkpoint-2026-09-22.log).
G0 is signed in `PROJECT_STATE.json`, merged in PR #21. This supersedes the
earlier public-test deferral; it does not prove the Phase 1 authentication flows.

## Phase 1 local evidence — 2026-09-28

On merged `main` at `3e8f96a`, from Person Two's own Windows PC: web lint and build
passed, Playwright passed 69/69 across the three viewports, the `db`-profile backend ran
against the local Docker Postgres with health and readiness `UP`, and Bruno passed 20/20
requests and 42/42 assertions. The sanitized records are in
[`evidence/P1/windows/2026-09-28/`](../../evidence/P1/windows/2026-09-28/README.md). This
attaches the local database/Bruno evidence the items below asked for.

## Still pending

- ~~Attach sanitized local Playwright, database and Bruno evidence~~ — done
  2026-09-28 on the current `main` (see above); it supersedes the older checkout.
- Complete the joint Phase 1 contract review before authentication feature work.
  G0 sign-off does not freeze the new Phase 1 auth contract.
