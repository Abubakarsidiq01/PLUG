# Person Two — Phase 1 setup record

Recorded by Person Two (`@uzom-a`) on 2026-09-21, following
[person-two-phase1-handoff.md](person-two-phase1-handoff.md) on her own
Windows 11 computer.

- **Checkout:** merged `main` at `938d5f3fabc0031df64781761f73bc131d8da580`
  (PR #10).
- **Toolchain:** Git, Node, GitHub CLI, Docker Desktop 29.8.0 and WSL2 (Ubuntu,
  version 2) were already present. pnpm 9.15.9, Bruno CLI 4.1.0 and Temurin JDK
  21.0.12 were installed during this session. The exact Node version was not
  recorded; Person Two must supply `node --version`.
- **Web browser tests (operator-reported):** two desktop accessibility cases
  (`public-shell`, `admin-login`) timed out on the first cold run; a targeted
  accessibility rerun passed 6 of 6. The original report also stated 21/21, but
  did not establish whether that was a separate complete run. A clean full-suite
  result and its report still need confirmation.
- **Backend:** `docker compose -f infra/compose.yml up -d --wait` started a
  healthy Postgres; `bootRun` with the `db` profile started in about 6 s and
  `/actuator/health` returned 200.
- **Bruno:** `bru run --env local` from `tests/api` passed 4 of 4 requests and
  11 of 11 assertions.

## Setup corrections

1. Open a new terminal after `winget` installs; Java is not on PATH otherwise.
2. The first `docker compose up` failed to pull the Postgres image with a TLS
   error and succeeded on retry (documented in `windows.md`).
3. `--env staging` cannot resolve while staging is deferred (ADR-004).
4. `fixtures/README.md` omitted `rate-limited.json`.

These are Person Two's reported results on the recorded checkout. Sanitized
local logs/reports have not yet been attached to this record. They do not prove
the later dependency revision or substitute for the pending public API run.

## Still pending

- Record the exact Node version, command/date/checkout for a full browser-suite
  run, and sanitized Playwright/Bruno summaries under `evidence/P0/`. Keep the
  observed timeout and rerun history; do not silently overwrite it.
- Public API run from this machine; needs a fresh tunnel URL from Person One
  (ADR-005). Do not reuse an old Quick Tunnel hostname.
- Person Two's own review of the Phase 0 evidence and contracts, and any
  approval of them. Nothing here records an approval or signs G0.
