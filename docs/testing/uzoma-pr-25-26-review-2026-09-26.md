# PR #25 and #26 integration review — 2026-09-26

Reviewed #25 at `de6a04e489dd4a70cb03a313363de0b6461bd174`, #26 at
`72c823cbc235e447e4b36d364f0dd446a4f290e5`, against #27 at
`62ea101e61a6ae4fdc039fa73c544a77496a0dce`. All six CI workflows passed
on each head. No changes or review comments were posted to Uzoma's branches.

## Findings and fixes

1. **P1 — Reconcile the auth contract before merging #25 with #27.**
   #25 `contracts/openapi.yaml:324–391` requires guest `device_id`, nested
   terms/privacy consent, flat session fields, `chl_` challenges and relative
   expiry. #27 implements guest `consent_version`, nested account/session
   metadata, `cha_` challenges and absolute expiry. #25 documents 200 for
   session creation; #27 returns 201. Against the isolated test backend on
   port 8082, #25's guest fixture returned **400 validation_failed**, while
   the implementation's request returned **201**. Agree one contract, update
   examples and fixtures, and run them against backend contract tests before
   both owners approve it. Include Google, account/session/consent endpoints,
   sign-up/sign-in intent and account-exists/account-not-found behavior from
   #27. Neither unmerged branch is automatically the agreed specification.

2. **P1 — Remove or implement the unfulfilled auth retry guarantee.**
   #25 `contracts/openapi.yaml:92,117,167,242` promises the original result
   for repeated Idempotency-Key values on auth routes. Two valid guest requests
   with the same key both returned 201 with different access tokens on #27.
   Remove that guarantee from unsupported auth routes, or implement bounded,
   payload-aware idempotency with explicit replay/security tests. Keep the
   existing Phase 0 request-route guarantee intact.

3. **P2 — Align token policy and unavailable-provider errors.**
   #25 `contracts/openapi.yaml:218,385` proposes JWT access tokens and 30-day
   refresh expiry, whereas #27's ADR-006 implements opaque tokens, 30-day
   verified-account refresh and 7-day guest refresh. ADR-006 is itself in the
   unmerged #27, so this needs joint agreement, not a claim that #25 violates
   an already merged decision. #25 phone/start responses at lines 123–131
   omit the implemented **503 dependency_unavailable** (confirmed against the
   isolated backend). Align error codes and document disabled delivery so
   clients can show a useful recovery path. Update both ADRs and schemas if
   the team chooses a different policy.

4. **P2 — Increase #26 legal navigation touch targets.**
   `web/src/app/globals.css:87–104` leaves Back to home and footer links as
   text-sized targets. A headless Chromium fixture using the exact branch CSS
   and corresponding anchor markup at 390×844 measured 15px and 19px heights,
   below the project's `design/tokens.json` 44px minimum. This was a CSS/markup
   reproduction, not a full Next.js route run. Use inline-flex, min-height
   44px and suitable padding, preserve focus styling, and assert target bounds
   in the existing mobile Playwright checks. Typography tokens are defined;
   there is no missing-token finding.

## Integration work

Virtual merges against #27 found two conflicting files for #25:
`contracts/openapi.yaml` and `PROJECT_STATE.json`.

#26 has seven conflicts: `PROJECT_STATE.json`, `docs/phases/P1-TWO.md`,
`tests/e2e/phase0-accessibility.spec.ts`, `web/src/app/globals.css`, and the
three privacy/terms/support pages. Its home footer also overlaps #27's shared
layout footer; retain one global navigation, not both. Preserve #26's reusable
LegalPage and route/accessibility checks while reconciling approved copy,
metadata, consent versions and #27's security tests. Placeholder legal text is
explicitly labelled and is not treated as approved policy.

Agree the contract first. Then rebase/integrate the overlapping work in one
chosen order, resolving individual changes rather than selecting whole files.
Run backend contract/integration tests, OpenAPI checks, web lint/build and
Playwright route/accessibility/touch-target tests on the resulting combined
branch. Green checks on three separate heads do not validate their combination.

## Corrections made to #27 during this review

- Help/terms now distinguish creating an account (retains guest activity) from
  signing into an existing account (switches without merging guest activity).
- Help accurately describes the visible-but-unavailable phone option.
- ADR-007 records the owner's Phase 1 outbound OTP scope expansion and retains
  disabled-by-default delivery and required real-device SMS evidence.
- Strict SwiftLint passed. These are copy/documentation changes; the earlier
  98 backend, 43 iOS and 7 UI scenario results remain recorded separately in
  `phase1-pr-readiness-2026-09-25.md` and were not rerun for this review.
