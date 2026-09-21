# Finish Phase 0 on PR #10

Use this checklist with [PR #10](https://github.com/Abubakarsidiq01/PLUG/pull/10),
the [hardening test report](phase-0-hardening-2026-09-20.md), and
`PROJECT_STATE.json`. The code is ready for independent verification; G0 is
still unsigned. The earlier physical-iPhone proof remains valid historical
evidence, but repeat the joint check on the revision being reviewed.

## 1. Review the updated PR together

- Open the PR's **Checks** tab. Backend, Web, iOS, OpenAPI, Security and Windows
  onboarding must pass on the latest commit. The Windows Bruno step must run
  from `tests/api`.
- Both people review `contracts/openapi.yaml`, `contracts/CHANGELOG.md`,
  `contracts/examples/` and `fixtures/`. Record agreement to version `0.1.0`
  and the three operations in the PR. Contracts remain draft until that review.
- Person Two (`@uzom-a`) reviews the code and submits her own GitHub review.
  The PR author records their agreement separately; do not invent an approval.
- Verify the existing `main` protection/ruleset requires review and the relevant
  checks. Keep the evidence or a settings link in the checkpoint record.

The live ruleset inspection found **one required approval but an empty required
status-check list**. Finish this setting in GitHub:

1. Open **Settings → Rules → Rulesets → Protect Main Branch → Edit**.
2. Keep enforcement **Active**, the default-branch target, one required
   approval, stale-review dismissal and conversation resolution.
3. Under **Require status checks to pass**, add all seven uniquely named checks
   after the updated workflows have run: **Backend tests**, **iOS build and
   tests**, **Web build and tests**, **OpenAPI validation**, **Windows
   onboarding**, **Secret scan**, and **CodeQL analysis**. Select GitHub Actions
   as their source where offered. Keep the branch-up-to-date requirement.
4. Save the required checks now. Confirm `@uzom-a` has write access and obtains
   her own independent review of this PR. The existing one-approval requirement
   remains in force.
5. Save the [ruleset link](https://github.com/Abubakarsidiq01/PLUG/rules/23628998)
   and a screenshot showing the populated checks in the evidence record.

Enable **Require review from Code Owners** after the updated `.github/CODEOWNERS`
has reached `main` through the reviewed PR. At this inspection, `main` still
named only the PR author, while PR #10 adds Person Two. GitHub uses the ownership
file on the base branch, so the proposed file is not yet the active ownership
map for this PR. See [GitHub's CODEOWNERS documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners).
Record the post-merge ruleset check separately; do not claim it has already run.

The connected GitHub integration can read this ruleset but does not have
administration access to change it. This setting must be completed by a
repository administrator. Do not count an enabled checkbox with no selected
checks as enforcement.

## 2. Person Two: prove a clean Windows setup

Follow [Windows onboarding](../onboarding/windows.md), including the actual
Docker Desktop/WSL2 setup. At step 3, after cloning and entering `PLUG`, select
the PR branch **before** installing dependencies or starting the backend:

```powershell
git switch p0-one-manual-v3-reconciliation
git pull --ff-only
git rev-parse HEAD
git status --short
```

Record the SHA. A fresh checkout should have no tracked changes. Complete
steps 4–8 of onboarding; save the web result, Playwright result and the local
Bruno result. Keep `.env.local` and its password out of evidence. The full local
collection includes readiness and must run against her own local backend.
CI cannot prove the interactive install steps on her machine.

Person One also records a clean Mac setup using
[Mac onboarding](../onboarding/mac.md) on this branch. Existing caches and an
already configured checkout alone do not prove clean setup. Use a separate
clone and stop any old backend before starting another on port 8080. Keep the
existing local database password if reusing its volume; a new environment file
does not change the password inside an existing database.

## 3. Person One: start the live checkpoint on the Mac

Arrange a time when both people are present. From this project's root, start
the local Phase 0 stub in Terminal A:

```bash
cd backend
./dev bootRun
```

Keep it running. This default profile does not need a database. If the
database-enabled backend from onboarding is already running and healthy, use
that process instead. In Terminal B at the project root:

```bash
curl -i http://127.0.0.1:8080/health
curl -i http://127.0.0.1:8080/health/ready
.tools/cloudflared/cloudflared tunnel --url http://127.0.0.1:8080
```

The project-local tunnel executable exists on Person One's current Mac. On a
fresh Mac install it with `brew install cloudflared`, then use
`cloudflared tunnel --url http://127.0.0.1:8080`.

The local requests should return `200`. Without the `db` profile, database and
migration checks are `DISABLED`; that does not prove database readiness.
Copy the new `https://…trycloudflare.com` address from Terminal B and share it
with Person Two. Keep both terminals running. The address changes when the
tunnel restarts; do not put it in tracked app configuration.

## 4. Person One: run the app on a real iPhone

1. From the project root, run `open ios/Plug.xcodeproj`.
2. Select the **Plug** scheme and the connected physical iPhone. Use the
   existing signing team and bundle identifier.
3. Open **Product → Scheme → Edit Scheme → Run → Arguments → Environment
   Variables**. Enable `PLUG_API_URL` and set it to the current HTTPS tunnel
   base URL, without `/health` on the end.
4. Run the app from Xcode. Switch the iPhone to cellular data and tap **Retry**.
5. Capture the **Connected** screen, version and request ID. Find that exact ID
   in Xcode's `health_check request_id=…` log and the backend terminal. Save
   sanitized excerpts of both. Separate requests have separate IDs.
6. Turn off both Wi-Fi and cellular data. Tap **Retry**, wait for the failure
   state, then restore connectivity and retry successfully. Save both states.
7. Test the largest accessibility text size and VoiceOver: content must remain
   readable, scrollable and navigable, and Retry must be usable. Record the
   device model, iOS version and actual result.

The Xcode launch variable applies to an app launched from Xcode. Repeat that
launch after changing the tunnel URL.

## 5. Person Two: test the same tunnel from Windows

In a new PowerShell terminal at the repository root, substitute the current
tunnel base URL for `YOUR-CURRENT-TUNNEL`:

```powershell
Push-Location tests/api
bru run health.bru requests-create-success.bru requests-create-validation-error.bru --env local --env-var baseUrl=https://YOUR-CURRENT-TUNNEL.trycloudflare.com
Pop-Location
curl.exe -i https://YOUR-CURRENT-TUNNEL.trycloudflare.com/health/ready
```

The three Bruno requests must pass (`200`, `202`, `400`). Public readiness must
be denied (`401` with the current local-profile security configuration), while
Person One's direct local readiness check succeeds. Do not run the full local
Bruno collection against the public tunnel: readiness is deliberately private.
Record the actual Windows result while Person One observes the phone and logs.

## 6. Complete and review the remaining evidence

Create a dated record under `evidence/P0/` containing:

- Actual time, both participants, commit SHA, device/OS and tool versions.
- Clean Mac and Windows setup results, current PR/CI links and branch-rule proof.
- The iPhone request ID, matching client/backend logs, and Windows Bruno output.
- Phone success, failure/recovery, large-text and VoiceOver evidence.
- Web states at 360, 768 and 1280 px and a web accessibility scan with no serious
  or critical findings. Browser smoke tests alone do not prove accessibility.
- Review of the design tokens and Figma implementation checklist. Link real
  frames where available; explicitly record the missing design handoff.
- Security scan results and the test report's size-limit, rate-limit, token and
  logging regressions. Review the Phase 0 failure/security matrix in
  [Person One's checklist](../phases/P0-ONE.md) and
  [Person Two's checklist](../phases/P0-TWO.md). Record any missing live abuse
  and recovery, database dependency/pool/slow-query, malformed-response and
  network-isolation evidence as pending; configuration alone is not a pass.
  Run disruptive dependency checks only on an isolated local test instance.
- Reviewed limitations from [ADR-004](../decisions/ADR-004-defer-aws-use-tunnel.md):
  temporary URL, synthetic data only, unauthenticated validation stub, no durable
  cloud environment, and no proof of signed-token staging through this tunnel.

Use existing automated tests for their documented scope; distinguish them from
physical-device or live-session evidence. Do not mark a check passed if it was
not performed. Keep secrets and personal data out of committed screenshots/logs.
Stop the tunnel with Ctrl+C when the session finishes.

## 7. Update this same PR with the evidence

Keep G0 pending until both people have reviewed all applicable checks, resolved
blockers, and explicitly signed off. After actual agreement, update the tracker,
freeze the reviewed contracts as `frozen@0.1.0`, and append the real G0 entry to
`PROJECT_STATE.json` with both sign-off links, evidence path and limitations.
Update phase/next actions consistently only when the gate has passed.

Commit only the reviewed evidence and state files, and push to
`p0-one-manual-v3-reconciliation`; PR #10 updates automatically. Recheck CI and
the independent approval on the final revision before merging. The signature
example in the older completion guide is a template, not an actual approval.
