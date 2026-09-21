# Shared checkpoint tracker

One row per feature. `PROJECT_STATE.json` is the machine-readable summary of
where this has reached.

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
| P0.S7 | iOS Xcode project, APIClient, Engineering health screen | person_one | — | — | — | Runs on Simulator + a real device | Keychain untouched in P0 | 8 iOS tests pass; physical iPhone 13 Pro Max on iOS 26.6 matches screen/Xcode/backend request ID; see `evidence/P0/logs/device-hardening-checkpoint-2026-09-20.log` | building | Person One confirmed offline recovery, largest text and VoiceOver; screenshots and joint Person Two evidence pending |
| P0.S8 | GitHub Actions: backend, iOS, security, OpenAPI | person_one | — | — | — | All required checks green on a PR | CodeQL + gitleaks + Dependabot | PR #10: Backend, Web, iOS, OpenAPI and Security passed on the hardening source | building | Windows process-lifetime fix passed on 16b9c57; add Windows onboarding to the required-check list |
| P0.S9 | Security baseline | person_one | — | — | — | No high/critical finding open | Secret scanning, dependency scanning, env validation, safe logging | `EnvironmentSafetyCheck`, `docs/security/` | building | Staging TLS not yet provisioned |
| P0.S10 | Threat model + data classification | person_one | — | — | — | Reviewed at every gate | — | `docs/security/threat-model.md` | done | Revisit whenever a trust boundary changes |
| P0.S11 | HikariCP bounds, timeouts, graceful shutdown | person_one | — | — | — | Fails safe under load | Bounded pool, request/query timeouts | `application.yml`, `application-db.yml` | building | Not load-tested |
| P0.S12 | `PROJECT_STATE.json` | person_one | — | — | — | Present, accurate, jointly owned | — | `PROJECT_STATE.json` | done | — |
| P0.S1-two | Windows setup proof | person_two | — | — | — | Every documented command runs | — | Windows run 35558025459 | building | Hosted Windows commands passed; personal Docker/WSL setup deferred to Phase 1 under ADR-005 |
| P0.S2-two | `/web` public site + protected admin shell | person_two | — | — | — | `pnpm --filter @plug/web build` succeeds; protected route redirects | Admin fails closed, including forged cookies; server-side auth remains P1 | `web/`, Playwright `phase0-smoke.spec.ts` (21/21 passing locally, exact 360/768/1280 px) | building | Admin stays unavailable until real sessions exist |
| P0.S3-two | `design/tokens.json` + CSS/Swift generator | person_two | — | — | — | Generated files compile in both web and iOS | — | `design/generate-tokens.mjs`, `design/generated/`, wired into `ios/Plug.xcodeproj` and `web/src/app/globals.css` | done | — |
| P0.S4-two | Playwright baseline | person_two | — | — | — | `pnpm --filter @plug/web test:e2e` passes on a clean clone | — | 21/21 tests passing locally across 360/768/1280 px, including six axe scans; final CI also required | done | — |
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
