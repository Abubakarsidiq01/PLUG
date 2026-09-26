# Account and auth-page follow-up — September 25

IMG_4251 and IMG_4252 are preserved with conversion hashes in
`evidence/P1/phone/2026-09-25/followup`. They show an expired tunnel address and
the welcome layout that the user approved. The welcome layout is unchanged.

The local backend was healthy; the temporary public tunnel had expired. A new
quick tunnel was started, both the phone configuration and shared Xcode scheme
were updated, and the backend was restarted with the account-intent change.
Public health returned HTTP 200. An invalid synthetic Google token with the new
signup intent returned HTTP 401, confirming the new route is reachable and does
not treat an unverified token as an account.

Signup now rejects a previously registered, verified provider identity with
`409 conflict / account_exists` and offers Sign in. Sign-in to an unknown identity
offers Create account. These checks happen after Google/Apple token or phone OTP
verification. No account or session is created by a rejected signup. Omitted
intent preserves compatibility with earlier clients. Identity matching uses the
provider's stable subject; it does not merge accounts just because email strings
match. This follows [Google's backend verification guidance](https://developers.google.com/identity/sign-in/ios/backend-auth).

A guest creating a new account still upgrades in place. Signing in to an existing
account switches to that account without merging guest activity; Profile explains
this distinction. Tests use the separate `plug_auth_regression` database, never
the live phone-testing database (`plug_validation`).

The method-selection screens use a centered 320-point form group, left-aligned
heading and supporting text, a compact centered wordmark with back navigation,
provider-specific signup/sign-in labels, and an inline account switch. Legal
links remain at the bottom and content scrolls when needed.

Validation: 90 backend tests, 43 iOS unit/integration tests and six UI scenarios pass.
SwiftLint, OpenAPI lint and whitespace checks pass. The signed iPhone build was
installed and launched successfully. Screenshots are in `evidence/P1/simulator/2026-09-25/account-intent`;
the signup/sign-in captures were visually inspected for alignment and spacing.

Real Google sign-in was previously confirmed in the supplied device evidence.
The new duplicate-signup interaction is covered by server and client regression
tests; repeating it with the user's Google account still needs their provider
interaction. Apple and SMS remain unavailable with the current setup and are
hidden. A quick tunnel is temporary, not a permanent hosted backend. No G1
sign-off is claimed.


## Evening connectivity follow-up

The backend remained healthy on port 8080. The earlier cloudflared process was
retrying `Unauthorized: Tunnel not found`; Hikari logs also showed long execution
pauses consistent with Mac sleep. A new `tools/run-phone-tunnel.sh` launcher keeps
an idle-sleep assertion only while its tunnel is alive, checks public health,
and saves the working URL in the ignored phone configuration. It skips the
bundled cloudflared version's optional startup diagnostics, which stalled during
this session. Control-C releases the assertion and stops the tunnel.

A separate network issue was confirmed: the Wi-Fi resolver returned NXDOMAIN for
a registered tunnel that public DNS resolved. HTTPS health returned 200 when
using that public answer with normal hostname/certificate validation. The helper
now detects this and advises mobile data/another network; it does not change
system DNS. The shared simulator scheme uses localhost, so it no longer retains
an expired quick-tunnel address.

Earlier live Google requests at 15:02:08 and 15:02:17 returned 409 then 201. This
confirms a conflict response followed by successful Google authentication, but
the logs alone do not establish the exact UI interaction or which account was used.

Follow-up validation: shell syntax and whitespace checks passed; the signed phone
build passed and was installed. All 43 iOS tests passed again with the local scheme.
