# ADR-005: Complete Phase 0 Windows verification with automation

- Status: Accepted by Person One
- Date: 2026-09-20
- Scope: Phase 0 verification and Person Two's onboarding handoff

## Decision

Person One explicitly requested that the remaining Windows work be completed
with automation now, and that Person Two join at Phase 1 when available. This
changes the earlier plan to wait for her live participation in Phase 0.

Use the real `windows-latest` GitHub Actions runner for the reproducible Windows
commands: dependency installation, production web build, browser tests, Java
backend startup, the local Bruno collection, and project-state parsing. Keep
the physical iPhone and temporary public-tunnel evidence collected with Person
One. Do not describe an automated run as work personally performed by Person Two.

The initial corrected Windows run passed on commit `16b9c57`:
[Windows run 35558025459](https://github.com/Abubakarsidiq01/PLUG/actions/runs/35558025459).
Later changes add browser accessibility checks and screenshots; their results
must also pass before the final revision is considered ready.

## Deferred to Person Two's first Phase 1 session

- Her actual Windows computer setup: interactive tool installation, Docker
  Desktop, WSL2, trust prompts and the database-enabled local backend.
- Her independent reading of the Phase 0 contracts, fixtures, limits and
  verification evidence before agreeing the Phase 1 identity/consent contract.
- A public HTTPS API run from her own computer against the then-current agreed
  environment. The present temporary tunnel may no longer exist by that time.

The owner of this onboarding follow-up is Person Two (`@uzom-a`), coordinated by
Person One. Complete it at the start of Phase 1, before relying on her machine
for feature development. See the [handoff](../onboarding/person-two-phase1-handoff.md).

## Limits of this decision

Hosted Windows CI does not prove interactive Docker/WSL setup on her computer.
The hosted Windows API run uses its own local backend; the public tunnel smoke
was run from Person One's Mac and physical iPhone. No Windows public-tunnel run
or live two-person witness is claimed.

This decision does not invent Person Two's signature, freeze the contracts on
her behalf, bypass GitHub's required independent review, or sign G0. Record the
actual evidence and this accepted deferral in the PR; retain accurate pending
items until they are performed. The existing ADR-004 cloud-staging limitations
continue to apply.

## Update — 2026-09-22

Deferred item 3 (a public HTTPS API run from Person Two's own computer) was
completed for real, ahead of Phase 1, during a live joint session: Person One's
physical iPhone and Person Two's own Windows PC (PowerShell, `bru` CLI and
`Invoke-RestMethod`) both reached the same cloudflared Quick Tunnel within the
same session window, and Person One's iPhone request_id was independently
confirmed inside the backend's own terminal log. See
`evidence/P0/logs/connected-checkpoint-2026-09-22.log` and the accompanying
screenshots in `evidence/P0/ios/` and `evidence/P0/logs/`.

Deferred items 1 (interactive Docker Desktop/WSL2 setup, database-enabled local
backend on her own machine) and 2 (her independent reading of the Phase 0
contracts before the Phase 1 identity/consent contract) remain open and are
still owned by Person Two at the start of Phase 1.
