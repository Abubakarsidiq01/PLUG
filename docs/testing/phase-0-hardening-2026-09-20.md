# Phase 0 hardening verification

This change continues the existing Java/Spring, SwiftUI and Next.js foundations
and the temporary Cloudflare checkpoint accepted in ADR-004. It adds no product
endpoints, changes no OpenAPI response shape, and does not sign G0. The starting
revision was `ea13fd7`; results below concern the local working changes.

## Fixes

- Windows CI now starts Bruno inside `tests/api`, where `bruno.json` lives.
  Mac and Windows onboarding commands now use the actual Gradle and Xcode paths.
  The Windows Gradle wrapper is normalized in Git; `.gitattributes` retains
  CRLF on Windows checkout without producing a dirty tracked file.
- Encoded spellings such as `/v1/%72equests` now receive the same body-size and
  rate limits as `/v1/requests`. A regression test exercises a real HTTP server.
- JSON numbers and booleans cannot be silently converted into a string query.
  Oversized idempotency headers report `size`, not a Java parameter name.
- Signed JWTs missing `aud` are rejected without throwing a null-pointer error.
- Migration metadata failures return the documented `503` readiness response.
- Forwarded requests cannot read readiness or Actuator probes. Public `/health`
  still works. Real ingress must retain separate network restrictions.
- Unknown paths are redacted in logging context as well as the final request
  log. Request DTOs redact their query and location in diagnostic string output.
- The Phase 0 admin shell fails closed even with a forged cookie. Only the
  exact login placeholder bypasses the redirect; full authentication stays P1.
- iOS bounds health-response data while streaming, cancels the task when done,
  rejects invalid responses, and shows safe errors. The health content scrolls
  at larger text sizes and retry tasks are cancelled when leaving the view.
- Gitleaks now scans API collections and fixtures instead of excluding them.
  Dependabot points at the root pnpm workspace and lockfile.
- GitHub's history scan found a false positive in the original Bruno fixture:
  its synthetic idempotency value. `.gitleaksignore` records only that exact
  commit/file/rule/line fingerprint; fixture directories remain scanned.
- CI jobs have distinct names so each required check can be selected without
  the earlier duplicate `validate` and `build-and-test` names. The live main
  ruleset still needs its empty required-check list populated by an admin.

## Verification

- Backend: `./dev test databaseTest check --console=plain` with the existing local
  PostgreSQL credentials provided only to the test process. Unit/integration,
  real HTTP, PostGIS/Flyway and Checkstyle checks pass (24 backend tests and
  1 database test). See
  `backend/build/reports/tests/` for detailed results.
- Web: lint, production build and all 15 Playwright cases pass across the
  mobile, tablet and desktop projects, including forged-cookie and login-prefix
  regressions. Report: `web/playwright-report/`.
- iOS: `xcodebuild test` on the installed iPhone 17 Pro simulator with Xcode
  26.6 passes all 8 tests, including offline/malformed/oversized responses and
  safe error messages. Result bundle is under the ignored
  `.xcode-derived-data-hardening/Logs/Test/` directory.
- Bruno: full collection executed from `tests/api` against a temporary local
  backend on port 18080; 4 requests, 4 script tests and 11 assertions pass.
- OpenAPI: Spectral reports no warnings or errors; provider contract tests pass.
- Generated design tokens reproduce the committed outputs without a diff.
- Gitleaks: a read-only snapshot of the working source, including fixtures and
  API collections, reports no leaks. After GitHub exposed the historical
  fixture false positive, Gitleaks 8.24.3 (the CI version) also passed the exact
  PR commit range and all locally available Git history (21 commits), using
  the single fingerprint exception above.

The tests reproduced the encoded-path limit bypass, scalar-to-string coercion,
MDC path exposure, migration-readiness exception, invalid header constraint
code, missing JWT audience crash, framework request-data logging and both admin
routing bypasses before fixes.

## Remaining verification

The corrected workflow has not been run on GitHub from these local changes.
Person Two still needs to complete the interactive Windows setup, and both
people still need the live checkpoint using the public-only Bruno command in
ADR-004. Physical-device and large-text/VoiceOver checks for this revision
remain part of that checkpoint. The existing earlier device evidence is
preserved. No cloud resources were provisioned and no gate was signed.
Follow [the joint-checkpoint walkthrough](phase-0-joint-checkpoint.md) for the
remaining steps and evidence to add to PR #10.
