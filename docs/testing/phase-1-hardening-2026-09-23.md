# Phase 1 hardening — September 23, 2026

Phase 1 now builds and runs locally after the fixes below. G1 remains unsigned:
physical Apple sign-in/relaunch, device accessibility evidence, approved legal
content, contract approval, and the joint staging checkpoint remain outstanding.
No reviewer, contributor attribution, commit, push, or deployment was added.

## Changes

- iOS logout refreshes expired access before requesting server revocation.
  Cancelled refreshes cannot put forgotten credentials back into storage.
  Failed Keychain writes do not replace the in-memory session; Keychain updates
  preserve the previous item if replacement fails. Session descriptions redact tokens.
- Transient restore failures preserve credentials. Retry restores the existing
  session. Guest upgrades refresh the guest token, have a visible Profile action,
  and keep the existing guest identity when the user returns to guest mode.
  Consent accepted by the server is saved for the next launch.
- Apple exchange strictly rejects expired tokens, including the JWT decoder's
  clock-skew window, which could otherwise outlive the replay record.
  OTP verification checks the incremented attempt budget and rechecks expiry,
  consumption, and budget at the database write. Tests always choose an actually
  incorrect code; the known-number test now creates an account first.
- Added `/terms`, `/privacy`, `/support`, shared navigation, browser security
  headers, and admin access tests. Legal routes explicitly await approved text.
  Admin stays closed in both the server page and proxy: Phase 1 has no admin
  issuer/MFA login. No frontend cookie grants access.
- Added 16 portable Bruno auth requests and wired the full collection into backend
  CI. The Windows job without a database explicitly runs its four baseline cases.
- Added a runnable `PlugUI` scheme. The old skipped target could not be run by the
  documented command. UI tests now assert success rather than photographing an
  unexpected error and passing. They scroll to controls at large text sizes.
- Added launch-screen/orientation metadata: the app previously rendered in a
  320×480 compatibility window. It now fills the device display. Long placeholder
  text scrolls, light appearance follows the design rules, and iOS foundation
  aliases use the shared generated tokens and rounded-rectangle controls.
- Removed 55 untracked duplicate “2” files: 49 exact copies and six superseded
  versions inspected against the current files. A recovery archive is retained
  at `/tmp/plug-redundant-copies-2026-09-23.tar.gz`. Generated backend duplicates
  also required a clean build. No user database was reset.

## Verification

All results below are local, on the working tree. Evidence is in
[`evidence/P1`](../../evidence/P1/README.md).

- Backend: `./backend/dev clean check databaseTest bootJar --no-daemon` —
  **28 baseline tests + 46 database/identity tests**, zero failures or skips;
  main/test Checkstyle and executable JAR build passed.
- iOS: `xcodebuild test ... -scheme Plug` — **36 tests**, zero failures or skips.
  Includes actual simulator Keychain operations and the live backend test.
- iOS UI: `xcodebuild test ... -scheme PlugUI` — **2 tests**, default and largest
  Dynamic Type; **14 screenshots** saved under `simulator/2026-09-23/`.
- Device compilation: unsigned `Release` build for `generic/platform=iOS` passed.
  This does not validate Apple provisioning or physical-device behavior.
- SwiftLint **0.65.1**, `lint --strict --no-cache`: zero violations in 26 files.
- Web: ESLint and optimized Next.js build/typecheck passed; **39 Playwright tests**
  passed across 360, 768, and 1280 px. Axe reported zero violations on all five
  routes at all three sizes. **15 screenshots** and axe summaries are saved.
- Live auth walkthrough: **35/35 assertions**. Bruno: **20/20 requests,
  42/42 assertions, 4/4 script tests**. Bruno tooling compatibility: **2/2**.
- `pnpm audit` and the locked Bruno `npm audit`: zero known advisories at every
  severity at validation time. This is not a JVM dependency audit.
- OpenAPI Spectral: zero warnings/errors. Shared design-token regeneration
  produced no changes. Terraform formatting and validation passed; no apply ran.
- Gitleaks **8.24.3**: 32-commit history and a snapshot of tracked/new source files
  passed. Four Phase 1 historical findings were synthetic examples/unsigned
  attack tokens; exact-value, exact-path rule exceptions preserve scanning of
  those files. The existing nonsecret Bruno idempotency fixture is also scoped.
- Live backend log inspection found no access/refresh tokens, authorization
  headers, phone numbers, or issued development codes. Local web/API response
  headers are saved separately; they are not external staging evidence.

SwiftLint was obtained from its [official release distribution](https://github.com/realm/SwiftLint/blob/main/SwiftLint.podspec).
The scoped Gitleaks exceptions use its [versioned rule-allowlist format](https://github.com/gitleaks/gitleaks/blob/v8.24.3/README.md#configuration).

## Running locally

The validation backend uses `http://127.0.0.1:8080`; the production web build uses
`http://localhost:3000`. The simulator runs the app against that backend.
The temporary `plug-phase1-validation` Docker container exposes Postgres at
`127.0.0.1:55432`, with database `plug_validation`, user `plug`, and test-only
password `local-validation-only`. The running backend uses test pepper
`local-validation-pepper-at-least-32-characters`. These values are disposable
local fixtures, never staging credentials. The existing container on port 5432
was left alone. Stopping the validation container removes its temporary data.

To restart the backend with this disposable database:

```sh
PLUG_DATABASE_URL=jdbc:postgresql://127.0.0.1:55432/plug_validation \
PLUG_DATABASE_PASSWORD=local-validation-only \
PLUG_IDENTITY_PEPPER=local-validation-pepper-at-least-32-characters \
./backend/dev bootRun --args='--spring.profiles.active=db --plug.identity.phone-delivery=development'
```

If the validation container has been removed, recreate it with:

```sh
docker run --detach --rm --name plug-phase1-validation --platform linux/amd64 \
  -e POSTGRES_DB=plug_validation -e POSTGRES_USER=plug \
  -e POSTGRES_PASSWORD=local-validation-only \
  -p 127.0.0.1:55432:5432 postgis/postgis:16-3.5
```

Do not run database tests while using the app against that same database: the
identity suite truncates its tables. Keep Xcode derived data under `/tmp` to
avoid the Desktop metadata that caused code signing to fail during this pass.
Use a clean backend build if stale duplicated `.class` files appear.

## Remaining checks

Follow the [device and gate runbook](../runbooks/p1-gate-completion.md).
A connected iPhone 13 Pro Max was detected with Developer Mode enabled.
The initial signed build failed because its existing provisioning profile lacks
Sign in with Apple. Actual Apple sign-in requires account-owner provisioning
and interaction with the phone. UI screenshots cover a subset of the state matrix; VoiceOver,
notifications denied, offline recovery, account conflict, and expired-code
physical evidence remain. Legal pages are shells until approved text is supplied.

Remote GitHub Actions (including CodeQL and the Windows runner), production,
external staging headers, and a new two-person checkpoint were not executed.
No G1 approvals were fabricated. SMS delivery and distributed rate limits remain
Phase 3; functional admin login/MFA remains Phase 5 under the existing plan.
Offline logout clears device credentials but cannot prove remote revocation
while the server is unreachable.

## Connected iPhone signing result

The connected iPhone is available, but Xcode provisioning refresh failed: the configured Personal development team does not support Sign in with Apple. Use an Apple Developer Program team that supports this capability, select it in Signing & Capabilities, enable the capability for the App ID, and refresh provisioning. Then follow the physical-device runbook. No phone app was installed or reset.
