# Phase 1: owner actions and completion order

Updated 2026-09-29. Read with [the G1 runbook](p1-gate-completion.md).
Google/guest phone acceptance is recorded in [phone evidence](../../evidence/P1/phone/2026-09-29/README.md).
PR #29 is merged. PR #30 fixes the local launcher and records validation; its
Windows font build failure is addressed by bundling the same IBM Plex Sans fonts.
No skipped test or disabled check is used as a fix.

## 1. Apple membership: account owner action

A free Personal Team cannot provision this app's Sign in with Apple capability.
An eligible team is needed to satisfy the blueprint's real-device Apple exit
criterion. Google success does not replace that criterion automatically.

1. Sign in at https://developer.apple.com/account/ with your existing developer account.
2. Enroll in the Apple Developer Program if you choose to pay, or obtain legitimate
   access to an existing eligible team. Complete Apple's identity/payment steps yourself.
3. Wait until membership and team access are active. Enrollment submission alone
   does not mean provisioning is ready.
4. In Certificates, Identifiers & Profiles, enable Sign in with Apple for
   `com.abubakarsidiq01.plug.app101` under the correct team.
5. Open `ios/Plug.xcodeproj`, choose the Plug target, Signing & Capabilities,
   select that team and automatic signing. Add the Sign in with Apple capability.
6. After provisioning is valid, set `PLUG_APPLE_SIGN_IN_ENABLED = YES` in ignored
   `ios/Plug/Resources/Local.xcconfig`. Confirm the backend Apple client ID is the
   same bundle identifier. Rebuild using Plug -> your unlocked iPhone -> Command-R.
7. Sign in with Apple, force-close, reopen, confirm the same account, then sign out.
   Send a screen recording of the app states without credentials or account notifications.

The code, entitlement configuration, build and install can be handled on the Mac
once the eligible team is available. Apple identity/payment/trust prompts and
confirmation of the phone experience require the owner.

If membership is deferred, keep Apple disabled and Phase 1's strict Apple exit
criterion open. A scope change would need an explicit documented decision.

## 2. SMS: optional early delivery, not a substitute for Apple

ADR-007 originally defers delivery; its amendment permits optional Twilio OTP.
The mechanism is tested, but real receipt needs a sender and provider permission.
Two-way SMS/iMessage integration is later-phase work.

1. In Twilio Console, check Phone Numbers -> Manage -> Active numbers.
2. You need an SMS-capable sender owned by the configured Twilio account. If none
   exists, follow Twilio's offered trial/upgrade and sender-registration steps.
   Availability and destination rules depend on the account and number type.
3. A Messaging Service SID is optional in this implementation: an owned sender
   can be used instead. In ignored `secrets/auth.env`, retain your account SID
   and auth token and configure:

   ```dotenv
   PLUG_IDENTITY_PHONE_DELIVERY=twilio
   PLUG_SMS_FROM_NUMBER=+YOUR_TWILIO_NUMBER
   PLUG_SMS_MESSAGING_SERVICE_SID=
   ```

   Replace the sender placeholder with the real E.164 number. This is the Twilio
   sender, not your personal recipient number. Never put these secrets in Xcode.
4. If the account is a trial, verify the recipient in Twilio and meet any required
   destination/registration restrictions. Trial service is not a promise of free
   unrestricted production SMS.
5. Restart the backend using the steps below. Enable
   `PLUG_PHONE_SIGN_IN_ENABLED = YES` in ignored Local.xcconfig only once the
   provider is configured. Rebuild the phone app.
6. Enter your recipient number, confirm receipt, submit the code, reopen and
   sign out. Also try a wrong code and verify a controlled error. Do not send
   screenshots of live OTPs, tokens or provider credentials.

For no-cost local development, the existing development sender writes a code to
an ignored restricted file. It tests the flow but does not send an SMS, and must
not be enabled on staging or described as real phone-number verification.

## 3. Restart for physical testing

Do this only when a restart is needed; a new Quick Tunnel changes its URL.

1. Start Docker Desktop and ensure the existing Postgres container is running.
   Preserve its volume and the existing identity pepper.
2. Stop the old backend with Ctrl-C in its terminal. Do not kill unrelated Java
   processes. From the repository root run `sh tools/run-phase1-local.sh`.
3. In a second terminal run `sh tools/run-phone-tunnel.sh`. Leave both terminals
   open. The helper embeds the new API URL in ignored Local.xcconfig.
4. Serve the web app on its configured local port and use a separate HTTPS tunnel
   for it. In Xcode, Product -> Scheme -> Edit Scheme -> Run -> Arguments,
   set `PLUG_WEB_URL` to that web tunnel URL. Do not use localhost on the phone.
5. Select the Plug scheme and the physical iPhone, then Command-R. Check
   Engineering -> Connected before testing sign-in. Open Terms/Privacy/Support
   and confirm each reaches its intended page; the current legal text is a draft.

## 4. Remaining hands-on phone evidence

Use test accounts and keep personal notification banners out of recordings.

1. **Largest text:** Settings -> Accessibility -> Display & Text Size -> Larger
   Text; enable Larger Accessibility Sizes and move to the largest size. Capture
   welcome, sign-in, create-account, Profile and legal navigation. Check that all
   controls remain readable and reachable. Restore your preferred size afterward.
2. **VoiceOver:** Settings -> Accessibility -> VoiceOver. Traverse the app with
   left/right swipes and activate with double-tap. Confirm meaningful labels,
   logical focus order and usable consent links, provider buttons and logout.
   You can ask Siri to turn VoiceOver off if needed.
3. **Offline recovery:** with the app open, disable both Wi-Fi and cellular data.
   Attempt an API-dependent action. Record the error, restore connectivity, tap
   Try again and confirm recovery without restarting the app.
4. **Guest upgrade:** create a guest, then use a provider identity that has never
   registered with PLUG. Complete account creation. Backend evidence must show
   the same internal user ID and revoked guest session. Signing into an existing
   account intentionally switches accounts and is not proof of this upgrade.
5. **Apple persistence:** complete section 1 after eligible provisioning is ready.

Automated tests can cover layout and API behavior, but cannot attest to the
owner's VoiceOver experience or claim a physical Apple login that never happened.

## 5. Joint checkpoint with Uzoma

1. Agree a time and the exact commit under test. Keep PRs targeting main and
   auto-merge disabled.
2. Prepare an isolated staging-profile backend and database using separate
   migration/application credentials. Do not relabel the local db profile as
   staging; do not run truncating database tests against retained app data.
3. Both connect to the same fresh HTTPS endpoint. Uzoma runs the Bruno abuse
   collection and external web/header checks while the owner runs phone flows.
4. Record expected unauthorized/forbidden/rate-limit results, refresh rotation
   and replay, logout revocation, consent records, and correlated request IDs.
   Inspect logs for credentials. Record ADR-007's delivery limitation honestly.
5. Each person supplies their own acceptance/signature after seeing results.
   Then update PROJECT_STATE.json to G1 passed and begin Phase 2. No other
   person's signature can be manufactured by automation.

## 6. Legal and public-launch work

The [privacy review](../legal/plug-privacy-policy-review.md) is editable source,
not a published policy. Operator, country, contact and minimum age are confirmed.
The blueprint's Phase 1 work includes session revocation on account deletion;
that must be verified even though a full user-facing deletion flow is also an
App Store release requirement. Do not mistake successful logout tests for proof
of account deletion.

Implementation can cover deletion UI/API, revocation tests, approved retention
jobs, age/parental-permission controls and synchronized legal pages. Before
publishing, resolve the concrete operational decisions:

1. Confirm whether testing is invitation-only adults while teen safeguards are
   implemented; keep the intended eventual minimum age at 15+.
2. Set and approve actual retention periods for accounts, sessions, consent,
   audit records and backups. Do not copy example periods that are not enforced.
3. Identify who handles privacy requests, the mailbox provider, backup locations
   and supported launch regions. Verify privacy@plugapp.com receives mail.
4. Review Terms against the actual private-test service and approve final text.
5. Review any new deletion/age/consent contract changes together before changing
   the frozen API; implement and test them, then publish matching web/iOS/backend
   consent versions. Keep pending requirements visible until evidence exists.

## References

- [Apple membership options](https://developer.apple.com/support/compare-memberships/)
- [Twilio message sender and trial requirements](https://www.twilio.com/docs/messaging/api/message-resource)
- [Apple account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app)
- [ADR-007 and amendment](../decisions/ADR-007-phone-delivery-deferred.md)
