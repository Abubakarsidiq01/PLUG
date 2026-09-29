# Phase 1 completion preparation — 2026-09-28

G1 is **not passed**. The owner authorized implementation, review and sign-off
work, but physical Apple and the two-person staging outcome are not established.

## Verified

- PR #29 reviewed and merged, preserving Uzoma's commit. Its five sanitized
  Windows evidence files substantiate local setup; they explicitly exclude G1.
- OpenAPI info.version reconciled to the already implemented 0.2.2 intent change.
  Existing #25/#27 approvals cover the implementation/fixtures. Phase 1 contract
  entries are recorded frozen@0.2.2; no schema or behavior changed in this update.
- Canonical local launcher now reads .env.local and secrets/auth.env, requires
  the configured database/pepper, and does not silently substitute disposable
  credentials or force development OTP. The legacy launcher delegates to it.
- Explicit debug=false/trace=false prevents the inherited DEBUG environment flag
  from enabling framework response-body logging during phone authentication.
- 108 backend tests (39 unit, 69 database), build/Checkstyle, 69 production-web
  browser tests, web build and OpenAPI lint passed.
- 35 local auth/abuse assertions passed against an isolated database on port
  55433 and a separate development-OTP server on port 8084. No phone account
  database was truncated. This is not proof of real SMS delivery.
- 31 externally routed HTTPS checks passed; 16 request IDs were found in the
  backend log. The sanitized report contains no credentials. Credential-pattern
  inspection of that runtime log found no matching session tokens/Bearer values.
- Signed Debug build installed and launched on the paired iPhone 13 Pro Max,
  iOS 26.7. Existing app data was preserved. This proves deployment, not successful
  physical authentication, VoiceOver, relaunch or recovery.

## Limits requiring actual evidence or input

1. Owner confirmed the Apple team is still free. Sign in with Apple remains
   disabled because eligible provisioning is unavailable; no Apple success claimed.
2. Twilio credentials exist, but a read-only inventory found zero SMS-capable
   owned numbers, and the Messaging Service SID is empty. Delivery remains none.
   No number was purchased and no paid SMS was sent.
3. Follow-up: the owner supplied the privacy PDF and confirmed operator/contact
   details and age 15+. The revised review draft is in
   docs/legal/plug-privacy-policy-review.md. Approved Terms, deletion/retention
   procedures and teen safeguards remain pending; public notices are unchanged.
4. External tests used the **local db profile** through user-authorized Cloudflare
   tunnels. They do not prove the dedicated staging profile or simultaneous
   participation by both engineers. The blueprint's joint G1 checkpoint remains open.
5. Follow-up: physical screenshots were supplied and reviewed on 2026-09-29;
   see ../../phone/2026-09-29/README.md for Google/guest acceptance and two matched
   health request IDs. VoiceOver, largest-text, offline and Apple evidence remain open.

## Phone handoff

Backend: localhost:8080, existing persistent database on localhost:5432.
The fresh API origin is in ignored Local.xcconfig and embedded in the installed
Debug build. API and web origins are recorded in external-checks.json; quick
URLs expire when their processes stop. Wi-Fi DNS did not resolve the fresh API
hostname; use cellular/another network on the phone if needed. TLS verification
was retained during the external checks using public DNS resolution.

Test Google sign-in, force-close/reopen, logout, guest access and offline recovery.
Send Profile/Engineering/error screenshots and VoiceOver evidence. Apple and
real SMS cannot be marked complete with Google/guest screenshots.

## September 29 CI follow-up

PR #30's Windows job failed in the web build before Playwright or backend
startup: `next/font/google queries have exactly one entry` while resolving
IBM Plex Sans through Turbopack. The missing report warnings were downstream
consequences, not separate failing tests. Bundled unmodified IBM font assets
and their OFL license now replace the build-time Google font resolver; the
same family and four weights remain. Local production build, ESLint and all
69 production-browser tests passed with the local fonts. The new Windows
CI result must be checked on the pushed commit.
