# Phase 0 checkpoint evidence

Phase 0 is not complete until every item is recorded:

- [x] Backend unit tests pass locally; CI results still need verification after push.
- [x] OpenAPI validates locally, including shared examples and provider-response schema tests.
- [ ] iOS shared-fixture decoding test passes.
- [ ] Staging `GET /health` succeeds from a physical iPhone.
- [ ] The app renders service and environment.
- [ ] Network failure renders an honest retry state.
- [ ] Invalid response fails safely.
- [ ] The same correlation/request ID is located in app and backend logs.
- [ ] Screenshot/video, logs, test run, date, build, and known limitations are linked.

Record evidence in the tracker/PR; do not commit user data or secrets here.

## Remaining completion gates

- [ ] Real PostgreSQL/PostGIS migration check passes locally and in staging.
- [ ] Staging application is deployed behind HTTPS with signed-token protection on writes.
- [ ] iOS build, lint, fixture, offline, and invalid-response tests pass with full Xcode.
- [ ] Provisional design tokens are reviewed against the design handoff.
- [ ] Second engineer is in CODEOWNERS; both engineers review shared contract changes.
- [ ] Main branch protection and green required CI checks are verified on GitHub.
- [ ] Clean-checkout setup is repeated independently by the second engineer.

Database, staging, and iOS gates remain unchecked even though configuration and tests now exist. See `local-validation.md` for the scope of completed checks.
