# Phase 1 PR readiness — September 25, 2026

## Scope and results

This PR includes the Phase 1 identity/consent implementation and the subsequent
user-requested Google, phone OTP, security and native onboarding work. The user
approved the welcome layout; it is preserved. IMG_4255–4257 are stored with hashes
under `evidence/P1/phone/2026-09-25/accepted`: welcome, API Connected and Google
Profile. No credential files or developer-local OAuth configuration are committed.

Phone signup/sign-in use six-digit, expiring, attempt-limited codes. Ownership is
verified before account-exists/not-found responses. Signup cannot silently log
into or create a duplicate existing account. Phone input requires an international
number; iOS supports OTP autofill, resend cooldown and changing the number.
A visible phone entry explains availability while SMS setup is incomplete.

Twilio can use either a Messaging Service SID or a Twilio-owned SMS sender number
(`PLUG_SMS_FROM_NUMBER`). The service takes precedence if both are present.
Network calls have timeouts, provider failures cannot report success, and there
is no automatic retry that could send duplicate texts. Local development codes
are restricted to the local environment and owner-only file permissions on POSIX.
The simulator can use a temporary code-file path outside protected Desktop folders.

Guest creation upgrades in place; signing into an existing account does not merge
guest requests. Profile now states that distinction. Google verification checks
signature, audience, issuer, expiry, nonce and replay. Provider identities are not
merged by email. Admin routes fail closed until Phase 5 enrollment/MFA exists.

## Validation

Final verification completed September 26. Backend: 98 tests; iOS: 43 tests;
UI: six general scenarios plus the full phone signup/conflict/signin scenario;
web: 39 browser tests. Web build/lint, SwiftLint, OpenAPI validation, secret
scans and production dependency audit pass. The API walkthrough passes 35 assertions; Bruno passes 20 requests, four tests
and 42 assertions. Real SMS/Apple remain unverified.

Final counts and evidence are recorded in `evidence/P1/logs/pr-readiness-2026-09-25.json`.
Tests use the isolated `plug_auth_regression` database. Local phone UI verification
uses development delivery on port 8082, never the user's account database or live SMS.
The code-file test path must be outside macOS-protected Desktop folders.

## What Person One still needs for Phase 1

1. Enable Sign in with Apple with an eligible Apple Developer Program team, restore
   the Apple entitlement and provisioning, then complete a real-device Apple login.
   The current Personal team cannot enable that capability. Google success does
   not replace the blueprint's Apple acceptance requirement.
2. Record physical-device relaunch/session persistence, logout revocation,
   guest-to-new-account upgrade, offline recovery and VoiceOver operation.
   Automated checks support these flows but do not replace the required recordings.
3. For the requested real-SMS expansion, configure an SMS-capable Twilio sender
   and allowed recipients/countries, enable the phone build setting, and verify
   an actual delivered code. Neither a Messaging Service SID nor a sender number
   is configured currently. No real SMS delivery is claimed. Trial restrictions
   and sender registration still apply; local codes are not SMS.
4. Complete the joint G1 checkpoint with Person Two on the same ephemeral staging
   environment (ADR-004 permits a tunnel). Approve/freeze the updated contract and
   actual legal text/consent version, attach the remaining Windows setup evidence,
   correlate a request across both lanes, and obtain both G1 signatures.

## Remaining limits and later work

- Rate limits are process-local: keep one backend instance until the planned Redis
  enforcement is implemented. Phone numbers and identity subjects depend on a
  stable secret pepper; changing it breaks identity lookup. Use managed secrets
  before production.
- Quick tunnels are temporary. The testing launcher prevents idle sleep only while
  running; it detects Wi-Fi DNS failures but does not change network settings.
- Apple needs external provisioning; SMS needs external sender setup. The app
  does not pretend unavailable methods work. There is no PLUG password to reset;
  recovery follows the selected provider or phone OTP.
- Future iMessage/SMS conversations, stable webhook hosting, admin enrollment/MFA
  and later-phase product tabs are not completed by this authentication PR.
- Bundled/web legal notices remain private-testing drafts pending approval.

## Rollout and rollback

Apply V3 for Google identities, deploy the backend before clients sending `intent`,
and configure provider flags only after delivery/signing works. Earlier clients
can omit intent for compatibility. Disable a provider in the client and server
configuration to stop new use; retain migrations and existing identity data.
Do not run `databaseTest` against the phone-testing, staging or production database.
