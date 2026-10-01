# Close the joint-checkpoint evidence gap

The owner reports Uzoma verbally accepted the behavior. Main at 81fd0e2 contains
PR #29's successful local Windows checks and PR #31's design/browser checks.
PR #29 explicitly excludes joint staging; #31 adds no joint staging report.
Do not rerun her entire local setup. First attach any existing joint-run record.

## If the original joint run exists

Uzoma can add a short note to PR #30 with: date, commit, endpoint/environment,
tests she ran, results, a request ID and her acceptance. Link the sanitized
artifact or log. The owner can supply the matching server line. Do not claim
this was a staging-profile run if it was the local db profile through a tunnel.
Existing evidence closes the gap without a repeat when it covers the requirement.

## Otherwise, a focused joint run

1. Agree the commit and time. Person One keeps Docker, the identity-enabled
   backend, web server and both HTTPS tunnels running. Share the current API and
   web origins, never credentials. Capture `/health` and record the commit under
   test separately if its build metadata says `dev`.
2. Record the actual backend profile. The current phone tunnel uses `db`, not
   `staging`. For the strict staging-profile checkpoint, configure the required
   staging issuer/audience, identity settings and separate database migration
   credentials first (see application-staging.yml and the G1 runbook). Do not
   disable those checks merely to obtain a pass. A local-db tunnel run is useful
   external evidence, but requires an explicit scope amendment to replace that
   profile requirement.
3. Uzoma opens PowerShell in the repository, installs the locked Bruno CLI if
   necessary, and runs the auth folder against the shared current API origin:

   ```powershell
   npm ci --prefix tools/bruno --ignore-scripts --no-audit --no-fund
   cd tests/api
   & "../../tools/bruno/node_modules/.bin/bru.cmd" run auth --env staging --env-var "baseUrl=https://CURRENT-API-TUNNEL.trycloudflare.com"
   ```

   Replace the placeholder with the current origin. Do not publish raw reports
   or response bodies containing test access/refresh tokens. This folder tests
   guest authorization, refresh replay, logout, invalid credentials and consent;
   it does not prove real Apple/SMS delivery or every rate-limit case.
4. Uzoma records external web headers (replace the placeholder):

   ```powershell
   curl.exe -sSI https://CURRENT-WEB-TUNNEL.trycloudflare.com/privacy
   ```

   Verify CSP, HSTS, frame/content-type protections and the intended privacy page.
5. Person One records a controlled rate-limit/abuse run on isolated staging test
   accounts; do not use a development-code sender outside local. Use the existing
   verified abuse tests for phone cases while live delivery is deferred. Record
   any uncovered staging-rate-limit case instead of calling the folder a full suite.
6. The owner uses the phone while Uzoma tests. Save one request ID visible on
   the phone and the matching backend line. Confirm logout revocation, guest
   restrictions and Google session behavior; Apple/SMS are deferred by ADR-008.
7. Both review sanitized results and sign their own scope. Record limitations,
   commit and evidence location in PROJECT_STATE.json. No need to repeat the
   already accepted VoiceOver and phone screenshots unless behavior changed.

Automation can run the API/browser checks, correlate logs and prepare the record.
It cannot impersonate Uzoma's independent test or invent her approval.
