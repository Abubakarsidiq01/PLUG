# Phase 1 final PR integration check — 2026-09-26

**Code review: ready for the normal PR approval/merge process. Phase gate: G1 remains open.**

The revised branches form one ancestor chain: #27 → #25 → #26. #25 now
uses #27's contract unchanged, checks fixtures against schemas and real backend
responses, and correctly documents opaque tokens, intent and unavailable
providers. #26 retains one footer, shares the legal-page component, and tests
44px link targets at all three viewports. The earlier review findings are
resolved. No remaining critical/high code issue was identified in this pass.
This is not a guarantee that the entire application is defect-free.

## Verification of the combined tree

- Backend: 39 unit and 69 database tests, zero failures/skips; build and Checkstyle pass.
- Web: production build and lint pass; 69 browser tests pass against that build,
  including routes, accessibility, target dimensions and security headers.
- Bruno: 20 requests, four tests, 42 assertions pass against the freshly built API.
- OpenAPI: no warnings. Production dependency audit: zero advisories.
- Tracked-file and 48-commit history secret scans: no leaks.
- All six GitHub workflows passed on each fetched PR head. iOS code is unchanged
  by this cleanup; the existing passing iOS CI and recorded device/simulator
  evidence are retained. This pass did not repeat physical-device tests.

Exact reviewed heads and sanitized results:
[evidence record](../../evidence/P1/logs/final-pr-stack-2026-09-26.json).
The final cleanup commit triggers a fresh CI run; use its checks before merging.

## Cleanup and final corrections

Two wrong-OTP tests assumed `000000` could never be generated. Both now select
an incorrect code relative to the actual generated code, avoiding rare random
failures. Outdated Phase 3-only SMS statements in the gate runbook and tracker
now match amended ADR-007. The original review is labelled historical.

Five byte-identical PNG copies were removed (814,108 bytes); adjacent READMEs
preserve their labels, SHA-256 hashes and links to the retained originals.
Distinct historical evidence and the user-approved physical screenshots remain.
No tracked ignored files were found. Credentials, local environment/configuration,
build output, dependencies and raw test reports remain outside Git. Ignore rules
now also cover Xcode result/archive exports, IPAs and JVM diagnostic dumps.
Deleting these duplicate images does not shrink existing Git history; no history
rewrite or secret deletion was required.

## Merge order

1. Review and merge #27 into main.
2. Verify #25 now targets main (retarget if necessary), review its final diff and checks, then merge.
3. Verify #26 now targets main, review its final diff and checks, then merge.

Preserving commits with merge commits keeps the stacked ancestry straightforward.
If squash/rebase merge is used, rebase the remaining stack onto the new main
before merging it; do not merge repeated parent changes blindly. No PR was
merged by this review, and no engineer approval or G1 signature was fabricated.

## What remains — Person One

- Obtain Apple-capable provisioning, enable Sign in with Apple and perform the
  required physical Apple sign-in/relaunch/logout/guest-upgrade checks.
- Capture physical offline recovery, VoiceOver and the remaining state/text-size
  evidence. Existing Google screenshots do not prove these Apple requirements.
- Configure a real SMS sender and prove receipt on the phone for the requested
  Phase 1 phone expansion, or explicitly agree and document a deferral. Do not
  expose local development codes in staging.
- Supply reachable API/web URLs and run the joint checkpoint with Person Two.

## What remains — Person Two

- Attach sanitized personal Windows/database/Bruno evidence still listed in the
  tracker; hosted CI is not evidence of her local environment.
- Finish the staging auth/abuse collection and external security-header evidence
  (P1.S3/P1.S7). The portable collection covers only part of the abuse matrix.
- Complete consent/error/upgrade copy review (P1.S5); arrange approved Terms,
  Privacy and a real support contact with the owner before public launch.

## Joint gate before Phase 2

- Record both approvals and freeze the aligned auth contract.
- Agree/publish approved legal text and the matching consent version across surfaces.
- Complete the shared staging checkpoint: revocation, refresh replay, applicable
  access-boundary/abuse cases, log inspection and one correlated request in both
  lanes. Record explicitly accepted deferrals rather than marking them tested.
- Add both engineers' G1 signatures and evidence to PROJECT_STATE.json. Only then
  change current_phase to P2 and begin the next contract session.

The physical Apple outcome is an explicit Phase 1 requirement. Merging the PRs
alone does not satisfy it. Redis multi-instance limits, supplier-specific BOLA,
admin enrollment/MFA, and two-way SMS/iMessage remain later-phase scope.
