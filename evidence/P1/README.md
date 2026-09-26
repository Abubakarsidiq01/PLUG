# Evidence — Phase 1, identity and consent

Two kinds of thing live here, and the difference matters.

**What has been verified** is in `logs/` and `simulator/`. It was produced by running the
real backend against a real PostgreSQL database and the real app in the Simulator, and it
is reproducible with the commands below.

**What is still missing** is at the bottom of this file. None of what is here passes gate
G1. A gate is passed by two people in front of real staging (manual.docx §8.1 rule 10),
and no amount of automation substitutes for that.

---

## What is here

| File | What it shows |
|---|---|
| `logs/local-auth-walkthrough.txt` | 35 assertions over the whole auth surface against a running backend: guest sign-in, the guest scope limit, anonymous and forged-token refusals, admin denial, wrong codes, guest upgrade-in-place, refresh rotation, replay revoking the chain, BOLA/IDOR answering 404, consent, logout revocation, and both brute-force limits. |
| `logs/log-leak-inspection.txt` | The backend log from that run searched for every access token, refresh token, authorization header, phone number and one-time code it handled. Also records what the log *does* keep: correlation ids, route templates and audit actions. |
| `logs/request-id-correlation.txt` | The same request id appearing in the app's log and in the backend's log — the mechanic the connected checkpoint depends on (manual.docx §7 step 5). |
| `simulator/` | The sign-in screens, photographed by `PlugUITests/SignInScreenshotTests.swift`, at the default text size and at the largest one. |

## Reproducing it

```bash
# 1. Database and backend
docker compose --env-file .env.local up -d --wait postgres
cd backend
PLUG_DATABASE_PASSWORD=... PLUG_IDENTITY_PEPPER=... \
  ./dev bootRun --args='--spring.profiles.active=db --plug.identity.phone-delivery=development'

# 2. The auth surface, end to end
cd ..
sh tools/phase1-auth-walkthrough.sh

# 3. The screens
xcodebuild test -project ios/Plug.xcodeproj -scheme PlugUI \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

The rate limits are counted per caller address and live in the backend's memory, so a
second walkthrough inside fifteen minutes is refused — correctly. Restart the backend
between runs.

---

## What is still missing, and why nothing here replaces it

| Missing | Why it cannot be produced here |
|---|---|
| `ios/` — real-device captures | §12.3 requires a real device. The captures in `simulator/` are from the Simulator and are labelled as such. Run the same UI test on a physical iPhone and the output *is* the evidence. |
| Sign in with Apple, on a device | Apple's sign-in sheet needs a real Apple Account on real hardware, and the capability has to be enabled for the App ID in the developer portal first. The server side is covered by `AppleSignInTest` against a key the test controls; the client side is not exercised until somebody signs in. |
| Relaunch after Apple sign-in | The sentence this phase is judged on. `SessionStoreTests` and `LiveBackendTests` prove a session is restored from storage, but "force-quit the app on a phone and it is still signed in" has to be seen. |
| `a11y/` — VoiceOver walkthrough | Has to be driven and recorded by a person. |
| `failures/` — a recorded failure and recovery | The walkthrough exercises failures and the screenshots show the states, but §12.3 asks for a recording. |
| Staging | ADR-004: there is no standing staging environment. Everything here ran against a local backend, not against the tunnel. |
| Two signatures on `G1` | Only two humans can do this. |

## One finding worth carrying into the gate

The largest Dynamic Type size broke the Profile screen's label/value rows — the value was
clipped. It is fixed (`ViewThatFits` in `PlugApp.swift`), and the before and after are the
reason these captures are taken at both sizes rather than only at the default.

The tab bar's own labels still crowd each other at that size. The tab names come from the
screen inventory in manual.docx §13, so renaming them is a product decision rather than
Person One's to take alone — it is recorded in `open_risks` instead.

## September 23 hardening

See [the validation record](../../docs/testing/phase-1-hardening-2026-09-23.md).
New captures are under `simulator/2026-09-23/` and `web/2026-09-23/`.
The dedicated `PlugUI` scheme actually executes the screenshot tests; a missing
launch-screen declaration was also fixed so the app uses the full display.
These captures supersede the earlier compatibility-window screenshots.

## September 25 physical Google sign-in

[User-supplied iPhone results](phone/2026-09-25/README.md) show a Google account
in Profile. The two accompanying welcome screenshots are the pre-redesign UI.

## September 25 account and layout follow-up

[Additional phone evidence](phone/2026-09-25/followup/README.md) records the expired
tunnel error and the welcome layout approved by the user. The separate auth pages
and account-exists flow are covered in
[the follow-up record](../../docs/testing/account-intent-2026-09-25.md).

## September 25 accepted phone build and PR validation

[Latest user-supplied screenshots](phone/2026-09-25/accepted/README.md) show the
approved welcome, API connectivity and Google account.
[PR validation and remaining Phase 1 work](../../docs/testing/phase1-pr-readiness-2026-09-25.md)
separate the automated results from real-SMS/Apple and joint G1 requirements.
