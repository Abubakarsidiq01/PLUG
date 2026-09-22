# Shared checkpoint tracker

One row per feature. `PROJECT_STATE.json` is the machine-readable summary of
where this has reached.

## Current closeout — 22 September 2026

G0 is signed in PR #21. PR #22 brought the onboarding corrections into main;
PR #23 records Person Two's clean local 21/21 browser run. All seven CI jobs
passed on merged main `c855ca0`. The Phase 0 API is frozen at 0.1.0 following
Person One's explicit confirmation that both engineers agreed it.

The closeout adds real database pool-exhaustion, query-timeout and recovery
tests; see [their evidence](../evidence/P0/logs/database-resilience-2026-09-22.md).
`PROJECT_STATE.json` advances to P1.S1: joint identity/consent contract review.
The closeout changes still require their own PR checks and independent approval.

Accepted limitations remain: temporary HTTPS staging under ADR-004 and local
Windows setup report attachments under ADR-005. The actual public Windows test
is complete. No Phase 1 authentication implementation or G1 completion is claimed.

## Historical implementation snapshot — 20 September 2026

The rows and pending descriptions below are retained as the earlier snapshot;
use the closeout above and `PROJECT_STATE.json` for current status.

20 September hardening verification is recorded in
[the test report](testing/phase-0-hardening-2026-09-20.md). The current checkpoint
uses ADR-004's temporary tunnel. These checks do not sign G0. Windows verification passed on `16b9c57`;
the final expanded accessibility suite is also required to pass CI. Person One
accepted hosted Windows verification and Person Two joining at Phase 1 under ADR-005.
The remaining hands-on steps are in
[the joint-checkpoint walkthrough](testing/phase-0-joint-checkpoint.md).

**Security owner:** person_one (@Abubakarsidiq01) for backend/iOS/infra;
person_two (@uzom-a) for web/contracts/fixtures/QA and external security testing
(manual.docx §5, §27.1).
**Incident contact:** person_one (@Abubakarsidiq01) — see `docs/runbooks/` for
the per-incident-type playbooks (auth abuse, bad deploy, database restore,
leaked secret, provider outage, queue backlog).

| State token | Feature | Owner | Contract | Depends on | Flag | Acceptance | Security impact | Evidence | Status | Known limitations |
|---|---|---|---|---|---|---|---|---|---|---|
| P0.S1 | Monorepo, CODEOWNERS, CI | person_one | — | — | — | Clean clone works on both machines | Branch protection + native secret scanning enabled in GitHub settings (confirmed by person_one); gitleaks in `.github/workflows/security.yml`; CODEOWNERS workflow globs fixed to match real filenames (`backend.yml`/`ios.yml`, not `backend-*`/`ios-*`) | | building | Path filters removed from backend/ios/openapi workflows so a required check can't silently never-run on an unrelated PR; web.yml CI added (was missing) |
| P0.S2 | Backend skeleton (Spring Boot, Actuator, JPA, Flyway) | person_one | — | — | — | `./dev test` passes on a clean clone | N/A | `backend/build/reports/tests` | building | — |
| P0.S3 | `/health`, `/health/ready`, error envelope, correlation filter | person_one | draft@0.1.0 (pending joint review) | — | — | Contract test validates real responses against OpenAPI | Public health is minimal; forwarded operational probes denied | `ContractTest`, `ReadinessFailureTest`, `CorrelationFilterTest`, hardening report | building | Direct probes still require private infrastructure in durable staging |
| P0.S4 | `POST /v1/requests` validated stub | person_one | draft@0.1.0 (pending joint review) | P0.S3 | — | 202 on valid input, structured 400 on invalid | Strict schema validation, encoded-path limits, no persistence yet | `RequestControllerTest`, `RequestLimitsHttpTest`, Bruno `requests-create-*.bru` | building | — |
| P0.S5 | Local PostgreSQL/PostGIS via Docker Compose | person_one | — | — | — | `./dev databaseTest` passes against real Postgres | DB bound to 127.0.0.1 only | Verified live: `databaseTest` green, PostGIS + Flyway + JPA all initialise | building | Staging DB not yet provisioned |
| P0.S6 | Terraform skeleton + secret-storage plan | person_one | — | — | — | Plan reviewed by both engineers before apply | Encrypted, private, managed-secret RDS | `infra/terraform/database.tf`, `infra/README.md` | building | Not applied — needs a real AWS account, region and budget sign-off |
| P0.S7 | iOS Xcode project, APIClient, Engineering health screen | person_one | — | — | — | Runs on Simulator + a real device | Keychain untouched in P0 | 8 iOS tests pass; physical iPhone 13 Pro Max on iOS 26.6 matches screen/Xcode/backend request ID; see `evidence/P0/logs/device-hardening-checkpoint-2026-09-20.log` | building | Person One confirmed offline recovery, largest text and VoiceOver; three phone screenshots linked in `evidence/P0/README.md`; Person Two personal setup deferred under ADR-005 |
| P0.S8 | GitHub Actions: backend, iOS, security, OpenAPI | person_one | — | — | — | All required checks green on a PR | CodeQL + gitleaks + Dependabot | PR #10: Backend, Web, iOS, OpenAPI and Security passed on the hardening source | building | Windows process-lifetime fix passed on 16b9c57; add Windows onboarding to the required-check list |
| P0.S9 | Security baseline | person_one | — | — | — | No high/critical finding open | Secret scanning, dependency scanning, env validation, safe logging | `EnvironmentSafetyCheck`, `docs/security/` | building | Staging TLS not yet provisioned |
| P0.S10 | Threat model + data classification | person_one | — | — | — | Reviewed at every gate | — | `docs/security/threat-model.md` | done | Revisit whenever a trust boundary changes |
| P0.S11 | HikariCP bounds, timeouts, graceful shutdown | person_one | — | — | — | Fails safe under load | Bounded pool, request/query timeouts | `application.yml`, `application-db.yml` | building | Not load-tested |
| P0.S12 | `PROJECT_STATE.json` | person_one | — | — | — | Present, accurate, jointly owned | — | `PROJECT_STATE.json` | done | — |
| P1.S1 | Auth contract 0.2.0: Apple, phone, guest, refresh, logout, consent | person_one | — | — | — | Both approvals on the contract PR | Frozen error codes unchanged; no new code invented | `contracts/openapi.yaml`, `contracts/CHANGELOG.md`, seven new examples | contract | Draft until Person Two's review; implementation follows the contract as written |
| P1.S2 | Apple identity-token verification + iOS Sign in with Apple | person_one | — | — | — | A real Apple sign-in on a physical device | Signature, issuer, audience, expiry, nonce and single-use all checked server-side | `AppleIdentityVerifier.java`, `AppleSignInTest.java` (8 cases), `WelcomeView.swift` | building | Capability not yet enabled on the App ID in the developer portal |
| P1.S3 | Phone verification: layered limits, attempts, expiry, audit | person_one | — | — | — | Brute force stopped against real staging | Three independent limits; constant-time comparison; no code ever logged | `PhoneVerificationService.java`, `OtpRateLimiter.java`, `PhoneVerificationTest.java` (9 cases) | building | No delivery channel until Phase 3 (ADR-007); 503 in staging |
| P1.S4 | Guest identity and upgrade-in-place | person_one | — | — | — | A guest upgrades without losing the request in progress | `user_id` preserved; guest sessions revoked on upgrade; link conflict refused | `AccountService.java`, `GuestAndUpgradeTest.java` (9 cases) | building | Needs the connected checkpoint to demonstrate jointly |
| P1.S5 | `users`, `identities`, `sessions`, `consents` migrations | person_one | — | — | — | Flyway validates on a clean database | Append-only audit table; subjects and codes stored one-way | `V2__identity.sql` | building | `PLUG_IDENTITY_PEPPER` has no secret-storage home yet |
| P1.S6 | iOS Keychain credential storage | person_one | — | — | — | Session survives a force-quit and relaunch on a real device | `AfterFirstUnlockThisDeviceOnly`; out of backups | `KeychainStore.swift`, `SessionStore.swift`, 10 iOS tests | building | Relaunch proven in tests; real-device capture outstanding |
| P1.S7 | Short-lived access tokens, rotating revocable refresh | person_one | — | — | — | A replayed refresh token revokes the chain | Opaque server-stored tokens (ADR-006); 15 min / 30 day / 7 day guest | `SessionService.java`, `SessionLifecycleTest.java` | building | Not load-tested; one indexed read per request |
| P1.S8 | Server-side revocation on logout, deletion, security change | person_one | — | — | — | Logout verified server-side, not just in the client | Revocation is a row update, effective on the next request | `SessionService.java`, `SessionRepository.java` | building | Account deletion has no screen yet; the service path is tested |
| P1.S9 | Deny-by-default authorization + resource-level test endpoint | person_one | — | — | — | BOLA and IDOR attempts return 404 | `anyRequest().denyAll()`; ownership checked on every read and write | `SecurityConfiguration.java`, `MeController.java` | building | Supplier resource IDs do not exist until Phase 3 |
| P1.S10 | Admin step-up authorization | person_one | — | — | — | No admin mutation without a second factor | Admin scope plus `mfa_verified`; in place before the first admin route | `AdminStepUpAuthorization.java` | building | Allow path untestable until an admin identity exists (Phase 5) |
| P1.S11 | Welcome, sign-in and create-account screens with every state | person_one | — | — | — | One screenshot per required cell, real device, largest Dynamic Type | Invalid code, expired code, offline, rate limited, denied notification, link conflict | `WelcomeView.swift`, `CodeEntryView.swift`, `AuthenticationModelTests.swift` | building | `evidence/P1/ios/` is empty; captures outstanding |
| P1.S12 | Terms and Privacy links, consent copy, consent version | person_one | — | — | — | Consent version persisted and visible in audit data | Server refuses a version it never published | `ConsentNotice.swift`, `consents` table, `GuestAndUpgradeTest.java` | building | Web routes and a production domain are Person Two's and undecided |
| P0.S1-two | Windows setup proof | person_two | — | — | — | Every documented command runs | — | Windows run 35558025459 | building | Hosted Windows commands passed; personal Docker/WSL setup deferred to Phase 1 under ADR-005 |
| P0.S2-two | `/web` public site + protected admin shell | person_two | — | — | — | `pnpm --filter @plug/web build` succeeds; protected route redirects | Admin fails closed, including forged cookies; server-side auth remains P1 | `web/`, Playwright `phase0-smoke.spec.ts` (21/21 passing locally and in CI on aff4688, exact 360/768/1280 px) | building | Admin stays unavailable until real sessions exist |
| P0.S3-two | `design/tokens.json` + CSS/Swift generator | person_two | — | — | — | Generated files compile in both web and iOS | — | `design/generate-tokens.mjs`, `design/generated/`, wired into `ios/Plug.xcodeproj` and `web/src/app/globals.css` | done | — |
| P0.S4-two | Playwright baseline | person_two | — | — | — | `pnpm --filter @plug/web test:e2e` passes on a clean clone | — | 21/21 tests passing locally and in Web/Windows CI on aff4688 across 360/768/1280 px, including six axe scans | done | — |
| P0.S5-two | Bruno collection | person_two | — | — | — | Run from `tests/api`; local full suite and ADR-004 public tunnel cases pass | Readiness tested directly, never exposed through tunnel | Verified live locally: 4/4 requests, 4/4 script tests, 11/11 assertions | building | Public tunnel suite passed from Mac; Person Two's own-machine run deferred under ADR-005 |
| P0.S6-two | Contract examples + fixtures review | person_two | — | — | — | One fixture per outcome per operation | — | `fixtures/requests.create/*.json` | done | — |
| P0.S7-two | Figma implementation checklist | person_two | — | — | — | Every §13–§15 screen mapped, nothing invented | — | `docs/design/figma-implementation-checklist.md` | building | No real Figma file exists yet to link frames to |
| P0.S8-two | Windows onboarding doc | person_two | — | — | — | Every step runs without an undocumented prerequisite | — | `docs/onboarding/windows.md`, Windows CI | building | Automated commands proven on Windows; interactive installation deferred to Person Two's first Phase 1 session |
| P0.S9-two | Shared tracker with security-owner/incident-contact | person_two | — | — | — | Both fields present | — | This file | done | — |

**Status values:** not started · contract · building · connecting · evidence · done

A feature is `done` only when the connected checkpoint has run and its evidence
is attached. Merged code with no connected run is `building` — most Phase 0
rows are `building` for exactly that reason: the code is written and verified
by automated tests and, where possible, real local runs, but the manual's
`done` bar specifically requires the two-person connected checkpoint against
real staging (manual.docx §4.3, §27.1 exit criteria), which by design cannot
be satisfied by a single automated session.

ADR-005 records Person One's later decision to accept hosted Windows verification
and defer Person Two's personal setup to Phase 1. Historical two-person procedure
above must not be read as evidence that she participated or signed this gate.
