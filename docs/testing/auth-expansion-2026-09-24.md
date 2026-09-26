# Authentication follow-up — September 24, 2026

User requested separate signup/sign-in, Google, real phone OTP, and method-specific recovery.
Changes remain local; no commit, push, reviewer or contributor attribution added.

Implemented:
- Removed auth state layout animation and restricted session restoration to one launch attempt.
- Separate welcome, signup, provider, phone and recovery pages; navigation resets scroll position.
- International phone formatting validated before requesting OTP; ASCII six-digit code input.
- Official Google SDK 9.2.0, redirect handling, configuration guards, backend JWT verification
  (signature/issuer/audience/expiry/nonce/replay), and guest upgrade using the common account service.
- V3 forward migration for Google; OpenAPI 0.2.1 remains a draft awaiting joint review.
- Twilio SMS delivery with explicit configuration, bounded connection/request timeouts, no
  automatic retries, and no sensitive provider logging. Default delivery is unavailable;
  local file delivery must be explicitly selected for tests.
- Phone recovery uses fresh OTP; Google/Apple recovery uses their own account recovery.
  No email/password accounts have been added.

Validation:
- Backend: 31 ordinary tests + 55 database tests passed; Checkstyle passed.
- iOS: 38 unit/integration tests passed, including the real API on local port 8081.
- Three UI scenarios passed: normal text, largest accessibility text, signup/recovery routing.
  One normal-text run overlapped a test-server restart and failed; its isolated rerun passed.
- Physical-iPhone Release target built with signing disabled. This proves compilation, not
  provisioning or live provider behavior on a phone.
- Real-server auth walkthrough: 35 assertions passed (explicit development OTP sender).
- OpenAPI Spectral, SwiftLint and git whitespace checks passed.
- Gitleaks scan of tracked and nonignored source files passed; ignored downloaded dependencies
  and generated caches were excluded from the source scan.

The existing backend/tunnel on 8080 was not stopped. An updated test backend was started
separately on 8081 using disposable Postgres at 55432. Those tool-managed processes may
not persist after this session. Start the persistent user terminal as the setup guide describes.

Remaining: configure Twilio and Google and verify actual delivery/login on the physical phone;
Apple provisioning; approved legal content and existing G1 approvals. No live Google account,
real SMS delivery, or physical layout result is claimed by these local tests.

Setup: [auth-provider-setup.md](../runbooks/auth-provider-setup.md).
