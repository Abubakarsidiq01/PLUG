# Runbook — finishing Phase 1 and signing G1

Everything that can be automated is done and green. What is left needs a real
phone, a real Apple Account, and a second person. This is the order to do it in.

Steps 1–4 are Person One alone and can be done today. Steps 5–7 need Person Two.

A gate is not passed by code being merged. It is passed by two people, together,
in front of real staging (manual.docx §8.1 rule 10).

---

## Before you start

```bash
git checkout p1.s1-one-identity-and-consent
git pull --ff-only origin main   # if main has moved
```

You need `.env.local` with, at minimum:

```
PLUG_DATABASE_PASSWORD=<your local password>
PLUG_IDENTITY_PEPPER=<32+ characters, local only>
```

The pepper is new in Phase 1. Without it the `db` and `staging` profiles refuse
to start, which is deliberate — it keys the one-way values stored for phone
numbers, Apple subjects and one-time codes.

---

## Step 1 — Enable Sign in with Apple on the App ID

This is a browser step and nothing in the repository can do it.

1. developer.apple.com → Certificates, Identifiers & Profiles → Identifiers.
2. Open `com.abubakarsidiq01.plug.app101`.
3. Tick **Sign in with Apple**, save.
4. In Xcode, let automatic signing refresh the profile.

`ios/Plug/Resources/Plug.entitlements` is already committed and referenced from
both build configurations. Until the capability is enabled, a device build will
fail to sign; Simulator builds are unaffected.

**Send me:** nothing. Just say whether it saved cleanly, or paste the error.

---

## Step 2 — Prove the automated suites on your machine

```bash
docker compose --env-file .env.local up -d --wait postgres

cd backend
./dev check                                   # Phase 0 + contract tests + checkstyle
PLUG_DATABASE_PASSWORD=... PLUG_IDENTITY_PEPPER=... ./dev databaseTest
cd ..

xcodebuild -showdestinations -project ios/Plug.xcodeproj -scheme Plug   # pick a UUID
xcodebuild test -project ios/Plug.xcodeproj -scheme Plug \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

Expected: `BUILD SUCCESSFUL` twice, and `Executed 28 tests ... 0 failures`.

`databaseTest` takes a while — one Phase 0 test deliberately waits on a
cancelled query.

**Send me:** the last 5 lines of each command. If anything fails, the whole
failure block, not a summary of it.

---

## Step 3 — Run the live walkthrough

With the backend running in its own terminal:

```bash
cd backend
PLUG_DATABASE_PASSWORD=... PLUG_IDENTITY_PEPPER=... \
  ./dev bootRun --args='--spring.profiles.active=db --plug.identity.phone-delivery=development'
```

Then, from the repository root in another terminal:

```bash
sh tools/phase1-auth-walkthrough.sh
```

Expected: `RESULT: 35 passed, 0 failed`.

The one-time-code limits are counted in the backend's memory and are per caller
address, so a second run inside fifteen minutes is refused. That is the control
working. Restart the backend between runs rather than raising the limit.

**Send me:** the `RESULT:` line, and any `FAIL` lines above it.

---

## Step 4 — Capture the real-device evidence

This is the part that actually moves the gate forward.

### 4a. The screens, automatically

Plug the iPhone in, unlock it, trust the Mac, then:

```bash
xcodebuild -showdestinations -project ios/Plug.xcodeproj -scheme Plug   # find the device id
xcodebuild test -project ios/Plug.xcodeproj -scheme Plug \
  -only-testing:PlugUITests \
  -destination 'platform=iOS,id=YOUR-DEVICE-UDID' \
  -resultBundlePath /tmp/p1-device.xcresult
```

Note: **no** `CODE_SIGN_IDENTITY` overrides here. A device build signs properly,
which is why step 1 had to happen first.

The phone needs to reach the backend. `localhost` on the phone is the phone, so
set `PLUG_API_URL` in the Xcode scheme to a `cloudflared` tunnel (ADR-004):

```bash
cloudflared tunnel --url http://localhost:8080
```

Then pull the images out:

```bash
xcrun xcresulttool export attachments --path /tmp/p1-device.xcresult --output-path /tmp/p1-shots
mkdir -p evidence/P1/ios
# copy the PNGs across, keeping the names from the manifest
```

These are real-device captures at the default and largest text sizes, which is
what manual.docx §12.3 asks for.

### 4b. The things no test can do

Do these by hand on the phone and record them:

1. **Sign in with Apple.** Complete it with a real Apple Account.
2. **Force-quit the app** (swipe it away), reopen it. You must still be signed
   in. This is the sentence the whole phase is judged on.
3. **Sign out**, then confirm on the server that the session is gone — the
   backend log line for the next request should be a 401.
4. **VoiceOver walkthrough** of sign-in, screen-recorded, into `evidence/P1/a11y/`.
   Every control reachable and announced.
5. **One deliberate failure and its recovery**, recorded, into
   `evidence/P1/failures/`. Turning off Wi-Fi mid sign-in is the easy one — the
   app should show the offline state and say nothing was lost.

**Send me:**
- the file names that landed in `evidence/P1/ios/`,
- a yes/no on the relaunch surviving,
- the backend log line showing the 401 after logout,
- anything that looked wrong, especially at the largest text size.

I will wire the evidence paths into `PROJECT_STATE.json` and the tracker.

---

## Step 5 — The contract session with Person Two

Fifteen minutes, together. The contract is `contracts/openapi.yaml` at 0.2.0 and
it is **draft** until you both approve it. Go through:

- the token payload and the two lifetimes: 15-minute access, rotating refresh at
  30 days for a verified account and 7 for a guest;
- every error code, and the `invalid` / `expired` detail tokens on a bad code;
- the guest scope limit on `/v1/me/sessions` and whether you both agree with it;
- the consent version and what happens when it moves.

The implementation follows the contract as written. If the review changes the
contract, the implementation changes with it, in the same pull request.

**Send me:** anything you agree to change. I will do the contract and the code
together and move those eleven operations from `draft` to `frozen@0.2.0`.

---

## Step 6 — The connected checkpoint

Both of you, at the same time, against one running staging tunnel.

Run, together:

- Apple sign-in on the phone;
- a guest upgrading without losing what it started;
- logout, and the session being dead server-side afterwards;
- the BOLA and IDOR cases;
- the refresh-replay case;
- Person Two's Bruno auth collection and the abuse suite.

Find one correlation id that appears in **both** the iOS log and the backend log
in the same session. That single value is what makes this a checkpoint rather
than two people watching two screens.

**Send me:** that request id, the backend log lines around it, and which of the
cases above you actually ran.

---

## Step 7 — Sign G1

Only after steps 5 and 6. Append to `gate_log` in `PROJECT_STATE.json`, with
both signatures, the evidence path, and any known limitation stated plainly —
including that the phone brute-force cases were proved by automated tests rather
than against staging, because there is no code channel until Phase 3 (ADR-007).

**Send me:** the go-ahead, and I will write the entry, set `last_gate_passed` to
`G1`, move `current_phase` to `P2` and rewrite `next_actions`.

---

## What is deliberately not in this phase

Each of these is written into the phase that owns it, so it surfaces when you
get there rather than being remembered:

| Deferred | Lands in | Written in |
|---|---|---|
| Twilio code delivery; Redis-backed rate limits; supplier BOLA ids; a real home for the pepper | P3 | `docs/phases/P3-ONE.md` → *Carried in from Phase 1* |
| Admin scope and the step-up allow path; account-deletion screen; consent history in the admin console | P5 | `docs/phases/P5-ONE.md` → *Carried in from Phase 1* |
| Load-testing the per-request session lookup; sweep behaviour under load | P6 | `docs/phases/P6-ONE.md` → *Carried in from Phase 1* |
| Deny-by-default rules for new routes; the 404-not-403 ownership pattern; tab-bar labels at the largest text size | P2 | `docs/phases/P2-ONE.md` → *Carried in from Phase 1* |
