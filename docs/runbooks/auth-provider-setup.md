# Phone OTP and Google setup

The welcome page separates **Sign in**, **Create account**, and **Continue as guest**.
Sign in/create account opens provider choices. Only choosing phone opens the number form.
After provider verification, Create account rejects an existing identity and offers Sign in.
Sign in to an unknown identity offers Create account. Use the same provider each time:
different providers are not automatically merged by email. Creating an account from a
guest preserves the guest user ID; signing into an existing account does not merge guest activity.

These methods are passwordless in PLUG. **Trouble signing in?** asks which method was
used, then offers phone verification or the provider's own recovery page. PLUG does not
store or reset Google/Apple passwords. Email/password accounts are not implemented.

## Real SMS (Twilio)

1. Configure a Twilio account with an SMS-capable Twilio number. You can use that
   number directly, or create a Messaging Service with an SMS-capable sender.
   Complete the sender registration required for the destination country. A trial account
   can only text verified recipient numbers; enable the destination's SMS geographic permission.
2. Create the ignored file `secrets/auth.env` in the project root (`mkdir -p secrets`).
   Set these shell assignments to your real values, without posting them in chat:

   ```sh
   PLUG_IDENTITY_PHONE_DELIVERY=twilio
   PLUG_SMS_ACCOUNT_SID='your Account SID starting AC'
   PLUG_SMS_AUTH_TOKEN='your Auth Token'
   PLUG_SMS_MESSAGING_SERVICE_SID='your Messaging Service SID starting MG'
   # Alternatively, leave the Messaging Service SID empty and use a Twilio-owned sender:
   PLUG_SMS_FROM_NUMBER='+YOUR_TWILIO_NUMBER'
   PLUG_GOOGLE_SERVER_CLIENT_ID='your Web OAuth client ID ending .apps.googleusercontent.com'
   ```

3. Run `chmod 600 secrets/auth.env`. The server launcher reads this file automatically.
4. In the app, use a full international number: `+1 312 555 0123` or `+234 803 123 4567`.
   Spaces, parentheses and hyphens are normalized. A local number without country code
   cannot be submitted. Enter the six digits received by SMS.
5. If delivery fails, check Twilio Messaging logs for the provider's delivery error and
   sender/country restrictions. API acceptance means queued, not confirmed delivered.
   PLUG does not log the phone, code, provider response or credentials.

The default sender is `none` (honest unavailable message). `development` writes test codes
only to `backend/build/development-phone-codes.txt`; it sends **no SMS**. Never use that
mode to test actual delivery. OTPs expire after 10 minutes, are one-use, and have attempt
and request limits. No automatic provider retry can accidentally send duplicate texts.

## Google

1. In Google Cloud/Google Auth Platform, configure the app's consent screen, support contact
   and audience. Add your Google account as a test user while the app is in testing.
2. Create an **iOS OAuth client** for bundle ID `com.abubakarsidiq01.plug.app101`.
3. Create a **Web application OAuth client** for backend token audience. Copy its client ID
   into `PLUG_GOOGLE_SERVER_CLIENT_ID` in `secrets/auth.env`. No client secret belongs in iOS.
4. Create the ignored file `ios/Plug/Resources/Local.xcconfig`:

   ```xcconfig
   PLUG_GOOGLE_IOS_CLIENT_ID = YOUR_IOS_CLIENT_ID.apps.googleusercontent.com
   PLUG_GOOGLE_SERVER_CLIENT_ID = YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
   PLUG_GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.YOUR_IOS_CLIENT_ID
   ```

   Use the exact reversed iOS client ID from Google, not the web client ID. The project
   already loads these settings into the Google SDK and URL scheme in both configurations.
5. In Xcode, allow package resolution. Google's official SDK is pinned to 9.2.0.
   Rebuild/run. Choose Sign in → Google and complete the provider sheet. The backend
   verifies signature, issuer, web audience, expiry, nonce and single use before issuing
   a PLUG session. A matching email never bypasses verification or merges accounts.

## Run the server and phone

From the project root:

```sh
tools/run-phase1-local.sh
```

Leave that terminal open. If port 8080 is occupied, stop the old backend in its terminal
with Control-C before restarting. The launcher uses the existing disposable validation
Postgres on port 55432 by default. For a persistent development database, set
`PLUG_DATABASE_URL`, `PLUG_DATABASE_PASSWORD`, and a stable `PLUG_IDENTITY_PEPPER` in the
ignored env file. Do not run `databaseTest` against a database containing accounts you
want to keep: those tests clear identity tables. Flyway applies V3 automatically.

In a second terminal:

```sh
sh tools/run-phone-tunnel.sh
```

This verifies public health, saves the new phone URL automatically and prevents idle
sleep while testing. Leave both terminals and the Mac lid open. Control-C stops the
tunnel and removes the sleep assertion; it does not change system power settings.
Quick tunnels are still temporary and can expire. Restart this launcher and rebuild
if that happens. Stop any older tunnel before starting a new one.

If the launcher reports a Wi-Fi DNS failure, it has verified the same HTTPS endpoint
using public DNS without changing your Mac's network settings. Turn off Wi-Fi on the
iPhone and use mobile data, or try another network. The current Wi-Fi resolver may
reject the new address even while the tunnel and backend are healthy. The shared
Xcode scheme uses localhost for the simulator; physical Debug builds use the URL
embedded from Local.xcconfig.

If using a separately managed tunnel, save its URL with:

```sh
python3 tools/set-phone-api.py https://YOUR-CURRENT-TUNNEL.trycloudflare.com
```

Then select Plug and your iPhone in Xcode and press Command-R. A Debug phone build now
embeds this address, so launching from the home screen works too, and an old open Xcode
scheme cannot override it. Re-run the helper and rebuild whenever the tunnel changes.
Simulator builds still use `PLUG_API_URL` or localhost. Release builds do not use the
development address. Google client IDs remain in Local.xcconfig.

Phone has a visible entry point with an availability notice while delivery is disabled.
After real SMS is ready, add
`PLUG_PHONE_SIGN_IN_ENABLED = YES` to Local.xcconfig and rebuild. After Apple signing
is fully configured, add `PLUG_APPLE_SIGN_IN_ENABLED = YES`. Never enable a provider
just to remove the unavailable message.

When both sender settings are supplied, the Messaging Service takes precedence.
An ordinary personal phone number is not a Twilio SMS sender. This fallback removes
the Messaging Service requirement; it does not remove trial recipient limits,
sender registration requirements or provider charges. Apple remains gated by its
signing capability. Future iMessage/SMS conversations are separate from proving
ownership of a phone number; neither an entered number nor a message draft signs
someone in. PLUG uses OTP/provider authentication, not a separate phone password.

For no-cost **local OTP testing**, use the existing development sender instead of SMS:
set `PLUG_IDENTITY_PHONE_DELIVERY='development'` in secrets/auth.env, restart the local
backend, and enable the phone button in Local.xcconfig. Codes appear in
`backend/build/development-phone-codes.txt` on the Mac; copy the latest code for the
number you entered into the phone. This does not deliver a text or establish ownership
of a real number; it is local test data only. Do not use development delivery in staging
or production, or share the code file. Restore `none` and disable the button afterward.

Apple sign-in still requires a team supporting the Apple capability and a correctly signed
entitlement. The currently empty development entitlement permits the Personal Team build,
but does not enable Apple login. Phone and Google do not use that entitlement.

## Physical check

- Welcome fills the screen immediately; opening sign-in from a guest profile does not
  restart session restoration. Verify again after a cold launch and with large text.
- Create account → phone → real SMS → code → Profile says Phone. Sign out and sign back
  in with that number; confirm the same account and data return.
- Try one incorrect code, then correct it. Request another after expiry if needed.
- Create account → Google; sign out and sign back in with the same Google account.
- Trouble signing in shows only recovery appropriate to the selected method.

Official references: [Google iOS setup](https://developers.google.com/identity/sign-in/ios/start-integrating),
[Google backend verification](https://developers.google.com/identity/sign-in/ios/backend-auth),
[Twilio message API](https://www.twilio.com/docs/messaging/api/message-resource).
