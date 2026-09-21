# Phase 0 checkpoint evidence

Phase 0 is not complete until every item is recorded:

The current checkpoint uses the temporary tunnel accepted in
`docs/decisions/ADR-004-defer-aws-use-tunnel.md`. Its public-only Bruno command
runs from `tests/api`; check readiness directly on the host. Cloud deployment
and signed-token staging checks below remain deferred, not passed by the tunnel.
Person One subsequently accepted hosted Windows verification and Person Two's
personal onboarding at Phase 1 under ADR-005. This replaces waiting for her
live Phase 0 participation; it does not record an approval on her behalf.

- [x] Backend unit tests pass locally and in CI on code revision `aff4688`.
- [x] OpenAPI validates locally, including shared examples and provider-response schema tests.
- [x] iOS shared-fixture decoding test passes.
- [x] Temporary HTTPS tunnel `GET /health` succeeds from a physical iPhone.
- [x] The app renders status/version and the request ID without exposing configuration.
- [x] Network failure renders an honest retry state; Person One confirmed recovery.
- [x] Invalid response fails safely in automated iOS tests; no physical malformed-response demo is claimed.
- [x] The same correlation/request ID is located in app and backend logs.
- [x] Screenshots, logs, test run, date, source revision, and known limitations are linked.

Record evidence in the tracker/PR; do not commit user data or secrets here.
The latest physical-device record is
[`device-hardening-checkpoint-2026-09-20.log`](../../evidence/P0/logs/device-hardening-checkpoint-2026-09-20.log).
Person One also confirmed largest-text and VoiceOver checks on iPhone 13 Pro Max,
iOS 26.6. Offline, Connected and scrolled large-text screenshots are linked in
[`evidence/P0/README.md`](../../evidence/P0/README.md). Hosted Windows evidence and the
accepted personal-onboarding deferral are recorded in `evidence/P0/README.md`.

## Remaining completion gates

- [ ] Real PostgreSQL/PostGIS migration check passes locally and in staging.
- [ ] Staging application is deployed behind HTTPS with signed-token protection on writes.
- [x] iOS build, lint, fixture, offline, and invalid-response tests pass with full Xcode.
- [ ] Provisional design tokens are reviewed against the design handoff.
- [ ] Second engineer is in CODEOWNERS; both engineers review shared contract changes.
- [ ] Main branch protection and green required CI checks are verified on GitHub.
- [ ] Clean-checkout setup is repeated independently by the second engineer.

Local database checks pass; durable cloud staging remains deferred under ADR-004.
The current physical-device success does not sign the two-person G0 gate.
See the [hardening report](phase-0-hardening-2026-09-20.md) and
[remaining-work guide](phase-0-joint-checkpoint.md) for the current scope.
