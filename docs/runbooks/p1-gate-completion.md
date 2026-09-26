# Phase 1 — remaining device work and G1 sign-off

The current implementation and checks are recorded in
[the PR validation record](../testing/phase1-pr-readiness-2026-09-25.md).
G1 remains open. Simulator evidence does not prove physical Apple sign-in,
VoiceOver operation, or the two-person staging checkpoint.

## Local checks

Use Java 21, Node 22, Docker Desktop, and Xcode. Run `./backend/dev clean check`
for the backend baseline. Identity tests use `./backend/dev databaseTest` and
**truncate identity tables**: point `PLUG_DATABASE_URL` at a disposable test
database, never your development or staging database. Also provide
`PLUG_DATABASE_PASSWORD` and a test-only `PLUG_IDENTITY_PEPPER` (32+ characters).
The September 23 run used an isolated container on port 55432.

With an identity-enabled backend running on port 8080:

```sh
# From the repository root:
pnpm --filter @plug/web lint
pnpm --filter @plug/web build
pnpm --filter @plug/web test:e2e
npm ci --prefix tools/bruno --ignore-scripts --no-audit --no-fund
(cd tests/api && ../../tools/bruno/node_modules/.bin/bru run --env local)
sh tools/phase1-auth-walkthrough.sh
```

The walkthrough needs `--spring.profiles.active=db
--plug.identity.phone-delivery=development` on the backend. Development codes
stay local; do not share the ignored `backend/build/development-phone-codes.txt`.
Restart this local test backend before repeating the abuse walkthrough, because
its per-address limits intentionally survive between calls.

```sh
xcodebuild -showdestinations -project ios/Plug.xcodeproj -scheme Plug
# Substitute an installed simulator UUID:
xcodebuild test -project ios/Plug.xcodeproj -scheme Plug \
  -destination 'platform=iOS Simulator,id=SIMULATOR-UUID' \
  -derivedDataPath /tmp/plug-p1-build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
# UI tests use their own shared scheme and require the running backend:
xcodebuild test -project ios/Plug.xcodeproj -scheme PlugUI \
  -destination 'platform=iOS Simulator,id=SIMULATOR-UUID' \
  -derivedDataPath /tmp/plug-p1-build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
```

Keep build output outside a synced Desktop folder if signing reports “resource
fork, Finder information, or similar detritus.” The old `-scheme Plug
-only-testing:PlugUITests` command did not run the skipped UI target; use `PlugUI`.

## 1. Enable Apple signing

**Remaining blocker:** The Personal development team does not support Sign in with Apple. Use an eligible Apple Developer Program team, enable the capability for the App ID and app entitlements, and refresh provisioning. The current signed app is installed and Google login is confirmed; Apple remains disabled.

1. Sign in to [Apple Developer](https://developer.apple.com/account/).
2. Open **Certificates, Identifiers & Profiles → Identifiers** and select
   `com.abubakarsidiq01.plug.app101`.
3. Enable **Sign in with Apple** and save. This needs the account owner's access.
4. Open `ios/Plug.xcodeproj`. On the Plug target, choose your team in
   **Signing & Capabilities** and allow Xcode to refresh provisioning.
5. Connect and unlock the iPhone, trust the Mac, and enable Developer Mode if
   iOS requests it. Approve any on-device restart or trust prompt.

The unsigned iPhone Release build can be checked without a phone; it does not
prove that your Apple account has the required capability or provisioning.

## 2. Give the phone reachable API and consent URLs

Run the backend with the database profile and your own local secrets. For
an ADR-004 checkpoint, start a fresh HTTPS tunnel:

```sh
sh tools/run-phone-tunnel.sh
```

The launcher saves the fresh HTTPS URL in ignored `Local.xcconfig`. Rebuild with
**Plug → your iPhone → Command-R**; physical Debug builds use that embedded URL.
The simulator scheme stays on localhost. Set `PLUG_WEB_URL` to a
reachable web URL serving `/terms` and `/privacy`; a second tunnel can forward
port 3000. `localhost` on an iPhone refers to the phone, not the Mac.

The web routes now exist, but their legal text awaits approval. Do not treat the
placeholder pages or development consent date as published legal agreements.
Development file-based phone delivery must remain local; it is unavailable in
staging until Phase 3 (ADR-007).

## 3. Capture and verify on the physical iPhone

Select the phone as Xcode's destination and run the **Plug** scheme:

1. Complete **Sign in with Apple** using your Apple Account.
2. Force-quit PLUG, reopen it, and confirm the same account appears in Profile.
3. Sign out. Confirm the server audit contains `session.revoked` for that
   request. The automated live test separately proves the old credential gets
   401; the app does not automatically send a stale token after logout.
4. Sign in as a guest. In Profile choose **Create account or sign in**, then
   create a new account with Apple. Confirm the backend keeps the same user ID and
   revokes the weaker guest session.
5. Turn off connectivity during sign-in or restore. Confirm the offline state;
   reconnect and tap **Try again**. Record a failure and recovery in
   `evidence/P1/failures/`.
6. Turn on VoiceOver and walk the main flow: consent links, Apple sign-in,
   guest access, upgrade, and logout. Record in `evidence/P1/a11y/`.

For repeatable default/largest-text screenshots, run the **PlugUI** scheme on
the phone. The runner needs URLs passed explicitly; Run-scheme variables alone
do not configure its child application:

```sh
TEST_RUNNER_PLUG_API_URL=https://YOUR-API-TUNNEL \
TEST_RUNNER_PLUG_WEB_URL=https://YOUR-WEB-TUNNEL \
xcodebuild test -project ios/Plug.xcodeproj -scheme PlugUI \
  -destination 'platform=iOS,id=YOUR-DEVICE-UDID' \
  -derivedDataPath /tmp/plug-p1-device-build \
  -resultBundlePath /tmp/plug-p1-device.xcresult

xcrun xcresulttool export attachments \
  --path /tmp/plug-p1-device.xcresult --output-path /tmp/plug-p1-device-shots
```

Use a fresh result-bundle path for each run. Keep normal device signing enabled;
do not apply the Simulator signing overrides. Copy the named PNGs from the
export manifest to `evidence/P1/ios/`. These tests cover welcome, phone entry,
code entry/invalid code or unavailable delivery, guest Profile, and upgrade.
Expired-code, denied-notification, conflict, offline, and real Apple states
still need their own device evidence; the UI tests do not capture all of §12.

## 4. Finish the joint checks

With Person Two:

- Approve the draft 0.2.0 auth contract, then update its state to frozen.
- Approve and publish the actual Terms, Privacy Policy, and matching consent
  version. Review the onboarding/error/upgrade copy.
- Run the auth and abuse checkpoint against the same fresh staging environment.
  Capture external web/API security headers and one request ID in both logs.
- Record the phone-delivery limitation and any accepted staging-test deferral.
- Attach the remaining Windows setup evidence.
- Only then add both engineers' G1 signatures and advance `PROJECT_STATE.json`.

Admin account enrollment/MFA and its successful login path remain Phase 5 work;
all Phase 1 admin routes reject guest/member access on the server. Redis-backed
limits, SMS delivery, supplier BOLA coverage and managed pepper storage remain
Phase 3 work. No G1 signature is inferred from this hardening pass.
