# Person Two: join at Phase 1

Person One requested that the Phase 0 Windows checks be completed through
automation so you can join at Phase 1. The scope and deferred personal setup
are recorded in [ADR-005](../decisions/ADR-005-phase0-windows-automation-handoff.md).

## What is already implemented and tested

- Public web shell and admin placeholder that stays closed until real sessions
  are implemented in Phase 1.
- Shared tokens and generated CSS/Swift outputs.
- Bruno health, private local readiness, valid-request and validation-error cases.
- Browser regression coverage, including forged cookies and login-prefix paths.
- Automated accessibility checks and screenshots at 360, 768 and 1280 px.
- Real Windows CI for installation/build/tests, backend startup and local API
  requests. Reports are attached to the PR's Web and Windows workflow runs.
- Person One's physical-iPhone request traced through screen, Xcode and backend
  logs, plus reported offline recovery, largest text and VoiceOver checks.

## Your first session

1. Read `PROJECT_STATE.json`, PR #10, ADR-004, ADR-005 and the evidence under
   `evidence/P0/`. Confirm whether the PR has merged; do not assume it has.
2. Follow [Windows onboarding](windows.md) on your computer, including Docker
   Desktop and WSL2. If PR #10 is still open, use
   `p0-one-manual-v3-reconciliation`; after it merges, use `main`. Record the
   checkout SHA and any setup correction.
3. Run the full local Bruno collection from `tests/api`, with your own backend
   running in another terminal. Complete the documented browser test command.
4. Review `contracts/openapi.yaml`, `contracts/examples/` and `fixtures/` with
   Person One. Record your actual agreement; nobody has signed for you.
5. Start [P1-TWO](../phases/P1-TWO.md) only after the state has advanced to P1
   and the Phase 1 contract is agreed. The existing login placeholder must not
   become a client-only authorization check.

If public API testing is needed, obtain the current environment URL from Person
One. Do not reuse an old Quick Tunnel hostname from a past checkpoint. Signed
authentication is a Phase 1 contract concern; the Phase 0 tunnel is only the
synthetic validation stub described in ADR-004.
