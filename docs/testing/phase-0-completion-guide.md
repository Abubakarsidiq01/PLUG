**PLUG Phase 0 completion guide**

Current checkpoint override: the later accepted [ADR-004](../decisions/ADR-004-defer-aws-use-tunnel.md)
defers AWS and uses a temporary Cloudflare tunnel. Follow that ADR's public-only
Bruno command for the present checkpoint. Steps 6–7 below describe the deferred
AWS path; signed-token staging tests apply when that environment is introduced.
This original 16 September guide is not the current project-state snapshot.
For the current PR and remaining hands-on steps, start with
[the joint-checkpoint walkthrough](phase-0-joint-checkpoint.md).

Prepared from the production manual §27.1, its two Phase 0 appendices, the pasted work history, and the files in this checkout on 16 September 2026. This is a set of instructions, not evidence that deployment or testing has happened.

The current state is `P0`, step `P0.S1-two`, owned by `person_two`. Staging is recorded as `not-yet-provisioned`; the three contracts are `draft`; `gate_log` is empty. Much of the foundation code exists, but G0 has not passed.

The finish line is: both people can set up a clean clone, GitHub enforces review and checks, a physical iPhone calls the real HTTPS staging backend, Windows API tests pass against staging, failures and security controls are demonstrated, and both people sign the evidence.

Person One owns backend, iOS and AWS. Person Two owns Windows, web, contracts, fixtures and QA. Do the steps below in order; after the shared contract review, the Mac, Windows and infrastructure work can proceed alongside each other.

**1. Confirm the people and the account information**

1. Name the second engineer and obtain their GitHub username. Invite them to the repository with write access.
2. Replace `@person-two-placeholder` in `.github/CODEOWNERS` with that username. Confirm the security owner and incident contact in `docs/CHECKPOINT_TRACKER.md`.
3. Correct CODEOWNERS patterns for the existing workflow filenames: `backend.yml` and `ios.yml` do not match `backend-*` and `ios-*`. Assign ownership of CODEOWNERS itself as well.
4. Agree the AWS account, region, spending budget, deployment owner, and a staging hostname under a domain you control. `api-staging.plug.app` is currently a configured example, not proof of a working environment.
5. Arrange a Mac with full Xcode, a physical iPhone, and a Windows machine or Windows VM with the required Docker virtualization support.

**Done when:** both people have repository access and the real deployment inputs are recorded without credentials. If you are working solo, revise the manual's two-person gate explicitly before claiming compliance; do not invent a second signature.

**2. Review and freeze the actual API contract together**

Open `contracts/openapi.yaml`, `contracts/CHANGELOG.md`, `contracts/examples/`, and `fixtures/requests.create/` together. Agree these behaviors:

- `GET /health`: public `200`, with `status`, `version`, and optional `commit`; no database details or environment name.
- `GET /health/ready`: private operational check. Database and migration checks must be `UP` in staging; `DISABLED` is not staging proof.
- `POST /v1/requests`: valid request returns `202`; authenticated invalid input returns the documented `400` error envelope.
- Staging writes require a signed access token, matching issuer and audience, with `plug.requests.write` scope.
- Error envelope, `X-Request-Id` correlation header, environment names and base URLs.

Resolve the version mismatch: OpenAPI currently says `0.3.0`, while the changelog/tracker refer to `0.1.0`. Choose and document one contract version, then use that value in `PROJECT_STATE.json`. The backend build version is a separate concept.

Open a contract PR and record both people's sign-off before further implementation changes. After merging the agreed contract, replace `draft` with `frozen@<agreed-version>` for the three operations. Do not mark the phase complete.

GitHub does not require both listed CODEOWNERS to approve, and a PR author cannot approve their own PR. If the manual's “both approvals” means two GitHub Approve reviews, arrange two eligible reviewers other than the author. If the intended meaning is both engineers' recorded sign-off, jointly document that interpretation and enforce the other engineer's independent approval; do not silently weaken the requirement. See [GitHub CODEOWNERS behavior](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners) and [review approval rules](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/approving-a-pull-request-with-required-reviews).

**Done when:** the merged contract PR, both sign-offs, fixtures, changelog and state file agree.

**3. Prove the Mac setup from a clean clone**

Install Git, full Xcode and an iPhone simulator runtime, Java 21, Docker Desktop, Node 22, pnpm `9.15.9`, and SwiftLint. Open Docker Desktop and wait until its engine is running. Install the AWS CLI and Terraform for the infrastructure work.

Commit and publish the reviewed source changes before asking someone to clone them. The existing checkout contains substantial uncommitted work; a fresh clone cannot see it. Inspect `git status`, `git diff`, and `git diff --cached`, stage the intended files explicitly, and review the staged diff before committing. Keep local secrets and generated build caches out of the commit.

Use a new clone directory so existing caches and local configuration do not hide missing setup steps. At its root:

```bash
cp .env.example .env.local
npm install -g pnpm@9.15.9
```

Set a local-only `PLUG_DATABASE_PASSWORD` in `.env.local`. For this shell-formatted file, load the variables into your Mac terminal before starting services:

```bash
set -a
source .env.local
set +a
docker compose --env-file .env.local up -d --wait postgres redis
pnpm install --frozen-lockfile
node design/generate-tokens.mjs
cd backend
./dev test databaseTest check
./dev bootRun --args='--spring.profiles.active=db'
```

Keep that backend terminal running. In a second terminal:

```bash
curl -i http://127.0.0.1:8080/health
curl -i http://127.0.0.1:8080/health/ready
```

Expect `200`; health has status/version, and readiness has database and migrations `UP`.

Corrections to the older onboarding instructions: there is no root Gradle wrapper or configured `flywayMigrate`/`contractTest` task. Run the wrapper in `backend/`; Flyway runs when the database-enabled application/tests start. Copying `.env.local` does not automatically export its values into a Java process. The root Compose file does include both PostgreSQL and Redis.

**Done when:** a clean clone passes backend, real-database and style checks, and the onboarding document includes every prerequisite actually needed. Save the commit, versions and results under `evidence/P0/`.

**4. Prove Windows and the web shell**

On Windows, install Git, Node 22, GitHub CLI if using `gh`, Java 21 if running the backend locally, WSL2 and Docker Desktop. Complete any required restart, launch Docker Desktop and enable its WSL2 integration. Install the Bruno application if you want its GUI; its command-line runner is a separate installation.

In PowerShell, clone the reviewed branch into a fresh directory and run from the repository root:

```powershell
npm install -g pnpm@9.15.9 @usebruno/cli
pnpm install --frozen-lockfile
node design/generate-tokens.mjs
pnpm --filter @plug/web lint
pnpm --filter @plug/web exec tsc --noEmit
pnpm --filter @plug/web build
pnpm --filter @plug/web exec playwright install
pnpm --filter @plug/web test:e2e
pnpm --filter @plug/web dev
```

Open `http://localhost:3000`, then `/admin`. Check that the public shell renders and `/admin` redirects to `/admin/login` without a loop. The admin cookie check is a placeholder: it must not protect real administrative capabilities or data in Phase 0.

There are currently no `typecheck` or `test:unit` package scripts. The command above invokes TypeScript directly. There is also no `tests/api/health/` directory; the request is `tests/api/health.bru`.

If also proving the local backend on Windows, create `.env.local`, set its local database password, and set the same value in the PowerShell process environment before launching Java:

```powershell
Copy-Item .env.example .env.local
# Edit .env.local, then set $env:PLUG_DATABASE_PASSWORD to the same local value.
docker compose --env-file .env.local up -d --wait postgres redis
cd backend
.\gradlew.bat test databaseTest check
.\gradlew.bat bootRun --args="--spring.profiles.active=db"
```

Use either the PowerShell workflow above or a documented WSL workflow consistently; do not assume their installations and environment variables are shared.

**Done when:** Person Two repeats the documented steps independently, records the results and fixes `docs/onboarding/windows.md` wherever the instructions were incomplete.

**5. Finish CI and enforce GitHub protections**

1. Open a PR containing the reviewed changes. Observe real workflow runs for Backend, iOS, OpenAPI and Security, rather than relying on local reports.
2. Add web CI for install, lint, TypeScript, build and Playwright. There is no web workflow in this checkout.
3. Enable dependency alerts/scanning and cover the pnpm workspace as well as Gradle. The existing Dependabot file only covers Gradle and GitHub Actions; update coverage and retain dependency scan results. An update-bot schedule alone is not a recorded clean vulnerability scan.
4. Fix workflow triggering before making all jobs required. The Backend, iOS and OpenAPI workflows currently use path filters; requiring a workflow that never starts can leave unrelated PRs blocked. For Phase 0, running the required workflows on every PR is a straightforward option. See [GitHub workflow filtering](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax).
5. In repository Settings → Rules/Rulesets, or Settings → Branches, protect `main`: require PRs, independent/code-owner review, the actual successful check names shown on your PR, current branches and resolved conversations; dismiss stale approvals and block force pushes/deletion. Apply protections to routine admin work too. Confirm a PR cannot merge with a failed required check. See [protected branch settings](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches).
6. Enable secret scanning and push protection where supported, and keep the Gitleaks CI check. Availability for private repositories depends on your plan; if unavailable, record the limitation and agree how the required protection will be met. Do not expose the repository just to obtain a setting. See [GitHub secret scanning availability](https://docs.github.com/en/code-security/concepts/secret-security/secret-scanning).

**Done when:** required CI passes on an actual PR, ownership is recognized, branch protection is enforced, and settings screenshots plus run links are saved in `evidence/P0/security/`.

**6. Complete the staging infrastructure definition**

This is still engineering work. `infra/terraform/database.tf` defines the database layer only. It does not create the VPC, application hosting, load balancer, certificate, DNS, or identity provider. Running `terraform apply` now does not produce a complete staging service.

One implementation that fits the existing AWS direction is a Java container on ECS Fargate behind an HTTPS Application Load Balancer, with private RDS PostgreSQL. This is a proposed implementation choice, not a mandate from the manual.

Person One should prepare the missing infrastructure in a reviewed PR:

1. Choose the region and configure AWS CLI access with an appropriate named identity. Verify the target account with `aws sts get-caller-identity`.
2. Configure a budget and alerts. Budget alerts notify you; they are not a hard spending cap. Review the complete hosting estimate, including load balancer, database, networking and logs, together.
3. Configure encrypted remote Terraform state with access controls and locking. The current `versions.tf` has no remote backend configuration.
4. Define a VPC, public ingress subnets and private application/database subnets across at least two availability zones. Define the outbound path the application needs for image pulls, secrets, logs and identity-provider keys. See [Fargate networking](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-networking.html).
5. Define separate security groups: internet → load balancer on HTTPS; load balancer → application on its application port; application/migration runner → database on `5432`. Do not expose the app port or the database directly to the internet.
6. Supply the database configuration's `vpc_id`, `private_subnet_ids`, `application_security_group_id` and a currently supported PostgreSQL 16 minor version for that region. Keep encryption, private access, backups and deletion protection enabled.
7. Resolve Redis explicitly. Local Compose includes it, but the Java backend currently has no Redis dependency or Redis readiness check. Either provide the private cache and required checks to match the manual, or jointly record a scoped Phase 0 deferral. Its omission must not be described as tested cache readiness.
8. Define the application task/service, registry, logs, IAM roles and deployment procedure. Inject credentials from Secrets Manager through the runtime configuration; do not put secret values into images or Terraform variable files. See [ECS Secrets Manager integration](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specifying-sensitive-data-tutorial.html).
9. Define DNS, an ACM certificate and the HTTPS listener. Use a hostname you control, validate the certificate, and configure HTTP-to-HTTPS redirection if HTTP is exposed. See [AWS HTTPS listeners](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-https-listener.html).
10. Block public `/health/ready` and `/actuator/*` routes while preserving private load-balancer probes. Add request-size, request-duration and rate limits at ingress.

After completing the configuration and authenticating to the agreed account:

```bash
cd infra/terraform
terraform init
terraform fmt -check
terraform validate
terraform plan -out=phase0-staging.tfplan
```

Review the actual plan and costs together. Only then apply that reviewed plan:

```bash
terraform apply phase0-staging.tfplan
```

The plan is gitignored and may contain sensitive values; do not attach it to public evidence.

**Done when:** the reviewed network, private database, hosting, secrets, HTTPS and deployment configuration exist and have been applied to the agreed staging account.

**7. Configure staging identity, database access and deploy the API**

1. Configure an HTTPS identity provider that issues signed access tokens with an `iss`, `aud`, `exp` and the `plug.requests.write` scope matching the backend validators. Obtain a short-lived test token through that provider's supported flow. A resource server configuration validates tokens; it does not issue them. Full customer sign-in UI belongs to Phase 1.
2. Create a least-privilege runtime database role separately from the migration role. Use a private migration path to enable PostGIS and apply/validate the existing Flyway migration. The application currently runs Flyway on startup with separate migration credentials; removing those credentials would require changing the deployment design and application configuration together.
3. Supply these values through deployment configuration and Secrets Manager as appropriate:

```text
SPRING_PROFILES_ACTIVE=staging
PLUG_BIND_ADDRESS=<container or private application listener address>
PLUG_DATABASE_URL=<runtime JDBC URL using sslmode=verify-full and trusted RDS CA>
PLUG_DATABASE_USER=<runtime role>
PLUG_DATABASE_PASSWORD=<injected runtime secret>
PLUG_MIGRATION_DATABASE_URL=<migration JDBC URL using verified TLS>
PLUG_MIGRATION_DATABASE_USER=<migration role>
PLUG_MIGRATION_DATABASE_PASSWORD=<injected migration secret>
PLUG_JWT_ISSUER=<actual HTTPS issuer>
PLUG_JWT_AUDIENCE=<audience issued in the test token>
```

For an ECS container, listening on `0.0.0.0` inside the container is normally needed for the load balancer to reach it; the task's private networking and security group limit access. Leaving the default loopback bind will make it unreachable from the load balancer.

4. Build the reviewed commit from `backend/`, setting `GIT_COMMIT` to the deployed revision before building so health reports a useful revision:

```bash
./dev bootJar
```

Package the executable JAR in the reviewed Java 21 image, publish it to the agreed registry and deploy it. This packaging/deployment automation still needs to be created; there is no complete deploy command in the checkout.

5. Verify external HTTPS `/health`. Verify private `/health/ready` reports database/migrations `UP`. Use the dependency-aware private route as the load-balancer probe, or explicitly configure and test the Actuator readiness group to include the dependencies. The existing Actuator readiness settings alone do not demonstrate that.
6. Configure alarms for readiness failure, elevated 5xx, latency, database connections and repeated restarts. Record the deployment revision and rollback artifact.
7. Update `PROJECT_STATE.json` with the actual staging URL only after it works. Leave production unprovisioned for this phase.

**Done when:** the deployed commit serves HTTPS, validates real tokens, reaches its private database and fails readiness when a required dependency fails.

**8. Build and test iOS on the Mac, then use the physical iPhone**

1. From the repository root, regenerate tokens with `node design/generate-tokens.mjs`.
2. Open `ios/Plug.xcodeproj` in Xcode and choose the `Plug` scheme. Those are the current names; `PLUG-Staging` is not a checked-in scheme.
3. Add `design/generated/Tokens.swift` to the `Plug` target as a reference to the generated file. Do not create a second independently maintained copy. Confirm it compiles. Review the existing provisional `PlugColor`/`PlugSpacing` usage against the agreed token source.
4. Run SwiftLint and select an installed simulator with `xcrun simctl list devices available`. Substitute its real UDID below:

```bash
swiftlint lint --strict
xcodebuild -project ios/Plug.xcodeproj -scheme Plug \
  -destination 'platform=iOS Simulator,id=REPLACE_WITH_INSTALLED_SIMULATOR_UDID' \
  CODE_SIGNING_ALLOWED=NO test
```

5. Confirm the shared health fixture decoding test and API client failure tests pass. Fix failures before using their results as gate evidence.
6. In Xcode → Target → Signing & Capabilities, choose your team and a valid bundle identifier. Connect and trust the iPhone, enable Developer Mode when prompted, and select it as the run destination. Simulator signing settings are not the device-signing procedure.
7. In Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables, set `PLUG_API_URL` to the actual staging HTTPS base URL. Build and run on the phone. `localhost` on the phone is the phone itself.
8. Open Engineering. Verify Connected, Version, optional Commit and Request ID. Older references to service/environment fields are stale; the current public contract intentionally omits them.

If distributing a build that starts outside Xcode, configure its `PlugAPIURL` bundle value as well; Xcode launch environment variables are not permanent app configuration.

**Done when:** tests pass and the physical iPhone renders the known response from the deployed staging revision.

**9. Make the Bruno collection work with real staging**

The two existing write requests use `auth: none`; they will not pass against the secured staging backend unchanged.

1. Set `baseUrl` in the staging environment to the actual HTTPS API URL.
2. In Bruno, configure Bearer authentication for both `requests-create-success.bru` and `requests-create-validation-error.bru`. Reference an uncommitted secret or process environment variable, for example `{{process.env.PLUG_TEST_ACCESS_TOKEN}}`. Obtain that token using the identity provider configured in step 7. Never save the actual token in a `.bru` file or test evidence. See [Bruno environment variables](https://docs.usebruno.com/variables/overview).
3. Run from the collection directory:

```text
cd tests/api
bru run health.bru --env staging
bru run requests-create-success.bru --env staging
bru run requests-create-validation-error.bru --env staging
```

Expect `200`, `202`, and `400` respectively. The validation request also needs a valid token; otherwise an authentication failure does not prove input validation. See [Bruno CLI](https://docs.usebruno.com/bru-cli/overview).

4. Add negative authentication requests: no token, invalid/expired token and wrong audience should be rejected; a valid token without the write scope should return `403`.
5. Separate the public test of `/health/ready` being blocked from the private dependency-readiness test. Run the latter from an authorized private network path. The existing `health-ready.bru` expects a readiness body, so running the entire collection against the public URL would conflict with the required protection.
6. Retain sanitized request results and their correlation IDs.

**Done when:** Person Two runs the public staging cases successfully from Windows, and Person One records the private readiness result.

**10. Run the outstanding security and failure checks**

Treat these as tests still to perform, not as completed work implied by configuration files:

- Send a bounded series of requests to your own staging API until the configured limit returns a controlled `429`. Confirm the API remains usable after the limit window resets. Stop once the behavior is demonstrated; coordinate the test with the deployment owner.
- Submit an oversized request and confirm it is rejected according to the contract. Check both ordinary and streamed/chunked request handling where applicable.
- Verify database and any cache have no public access path using their subnet, route, public-access and security-group configuration; corroborate with an external connection attempt and successful access from the authorized application path. An external timeout by itself is not sufficient proof.
- Confirm the public endpoint contains no dependency/configuration details. Verify readiness/Actuator routes cannot be read publicly.
- Search sanitized client, API and infrastructure logs for your synthetic test credential and authorization-header patterns. Review `HealthView.swift`'s current raw error/URL debug prints and ensure diagnostics satisfy the safe-logging rule.
- In an isolated staging test, stop or block the required dependency, verify readiness fails, restore it and verify recovery. Avoid disrupting unrelated work.
- Add and prove query/transaction timeouts and request-duration limits. Current Hikari settings limit pool size and connection acquisition, but the shown configuration does not establish a database statement timeout; a Tomcat connection timeout is not an end-to-end processing deadline. Exercise bounded pool exhaustion and a deliberately slow test query, then confirm recovery and graceful shutdown.
- Retain dependency, secret and code-scanning results; fix high/critical issues before sign-off. Any exception allowed by the manual needs a named owner, mitigation, expiry and explicit reviewer acceptance; do not silently treat it as a pass.

The phase instructions reference an abuse collection, but `tests/api/abuse` does not currently exist. Create the applicable cases or record an equivalent reproducible test procedure and output.

**Done when:** each G0 security requirement has observable evidence and no unresolved blocking finding remains.

**11. Finish design, accessibility and evidence**

1. Review `design/tokens.json`, both generated outputs and `docs/design/figma-implementation-checklist.md` together. Link actual Figma frames where a real handoff exists. The checklist is a Phase 0 deliverable; a newly created full product Figma design is not itself a §27.1 exit condition.
2. Capture the relevant web states at exactly 360, 768 and 1280 px. Current Playwright device presets do not match these required widths; the existing nine smoke cases alone do not supply this screenshot evidence.
3. Capture the iPhone health success, loading and failure/retry states at default and largest Dynamic Type. Confirm the request ID remains usable and text is readable.
4. Run an axe accessibility scan for the web shell and address serious/critical findings. Perform a VoiceOver walkthrough of the phone's primary flow.
5. Create the evidence directories:

```bash
mkdir -p evidence/P0/ios evidence/P0/web evidence/P0/failures
mkdir -p evidence/P0/a11y evidence/P0/security evidence/P0/logs
```

6. Add an evidence index recording actual date/time, participants, commit/build, device/OS, staging URL, test result links, request ID and limitations. Sanitize logs and screenshots. The repository ignores `evidence/**/*.mov`; use committed screenshots and an accessible recording link if retaining a movie.

**Done when:** a reviewer can follow the evidence index and verify every applicable requirement without reconstructing the session from chat.

**12. Perform the connected checkpoint together**

1. Person One launches the real app on the physical iPhone against staging.
2. Trigger one health request. Copy the `X-Request-Id` value shown by the app, locate that exact ID in the iOS networking log and backend log, and save sanitized excerpts of both. Do not substitute a separate curl request's ID.
3. Person Two runs the staging Bruno success, validation and authorization cases from Windows while both people observe.
4. Turn off both mobile data and Wi-Fi on the test phone; retry, confirm an honest failure, restore connectivity and confirm recovery.
5. Demonstrate malformed-response handling using a controlled test endpoint or fixture server for the test build, then restore the real staging URL. Keep this evidence distinct from the real staging success. Do not break the shared public health endpoint to manufacture a bad response.
6. Demonstrate the agreed bounded abuse case, such as rate limiting, and verify recovery.
7. Review the evidence, CI, clean-clone results and all G0 criteria together. Run the manual's §8.4 audit against each person's surface and resolve blockers.

**Done when:** both people witnessed the success, failures and recovery, and the exact matching request ID is recorded in the tracker and evidence.

**13. Sign G0 and advance the state**

Only after all prior checks pass, append an actual entry to `PROJECT_STATE.json`:

```json
{
  "gate": "G0",
  "passed_at": "REPLACE_WITH_ACTUAL_DATE",
  "evidence": "evidence/P0/ — REPLACE_WITH_ACTUAL_REQUEST_ID_AND_CI_LINK",
  "signed_off": ["person_one", "person_two"],
  "known_limitations": "REPLACE_WITH_REVIEWED_LIMITATIONS_OR_NONE"
}
```

Record the real humans' names/handles and their sign-off links in the evidence index. The example above is a template, not a signature or proof.

Then update `last_gate_passed` to `G0`, `current_phase` to `P1`, `next_gate` to `G1`, and set the P1 step, owner, manual section, phase README, next actions and timestamps consistently. Remove resolved risks and retain only real limitations. Update the checkpoint tracker and merge the reviewed evidence/state PR. Schedule the Phase 1 contract session.

**Phase 0 is complete when all six exit conditions are evidenced:** clean clones on Mac and Windows; protected main and active ownership; physical iPhone reaches staging; Windows shell works and staging API tests pass; no unresolved high/critical security finding; and a real, jointly signed G0 entry.
