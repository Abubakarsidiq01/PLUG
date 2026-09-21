# Dependency maintenance — 2026-09-21

This consolidates the 13 Dependabot proposals opened before/after Phase 0 PR #10.
It preserves the Spring Boot 3 / Jackson 2 backend and current Next.js toolchain.
Do not merge an incompatible major version just to clear a red check.

## Disposition of the original PRs

| Original PR | Proposal | Consolidated decision |
| --- | --- | --- |
| #2 | setup-java 6 | Included in all affected workflows. |
| #3 | checkout 7 | Included. Its failed Windows run was an npm tarball 404 during Bruno installation, not checkout. |
| #4 | Gradle 9.7.1 | Included with wrapper JAR, scripts and distribution checksum. |
| #5 | json-schema-validator 3.0.7 | Deferred: the existing `JsonSchemaFactory` / `SpecVersion` API no longer compiles. Keep 1.5.9 until contract-test migration is reviewed. |
| #6 | Spring Boot 4.1.1 | Deferred: Jackson and Boot configuration packages used by JSON hardening no longer compile. Keep 3.5.16 pending an explicit backend migration. |
| #7 | CodeQL action 4 | Included for init and analyze. |
| #8 | setup-node 7 | Included; application runtime remains Node 22. |
| #9 | upload-artifact 7 | Included in all affected workflows. |
| #11, #14 | React DOM / React 19.3.0 | Included together, with one regenerated pnpm lockfile. |
| #12 | ESLint 10.10.0 | Deferred: `react/display-name` crashes because `contextOrFilename.getFilename` is unavailable. Keep ESLint 9. |
| #13 | Node typings 26.6.1 | Replaced with Node 22 typings (22.20.4), matching the actual runtime. Revisit with a Node runtime upgrade. |
| #15 | TypeScript 7.0.2 | Deferred: typescript-eslint explicitly rejects TS 7. Keep TypeScript 5.9.3. |

Original failure logs:
[Boot](https://github.com/Abubakarsidiq01/PLUG/actions/runs/35643661967),
[validator](https://github.com/Abubakarsidiq01/PLUG/actions/runs/35643661424),
[ESLint](https://github.com/Abubakarsidiq01/PLUG/actions/runs/35643588095),
[TypeScript](https://github.com/Abubakarsidiq01/PLUG/actions/runs/35643658495),
[checkout/Bruno download](https://github.com/Abubakarsidiq01/PLUG/actions/runs/35643664418).

## Reproducible Bruno tooling

`tools/bruno/package-lock.json` locks the CLI and its transitive dependencies.
Windows CI and onboarding use `npm ci` and the repository-local executable,
instead of installing a moving global dependency tree. This prevents silent
version drift; it cannot guarantee registry availability.

Bruno 4.1.0 is the current CLI release checked during this change. Its upstream
tree contained audit findings in Axios, form-data, nanoid, Faker, CSV parsing and
UUID. Explicit overrides select patched versions; the full HTTP collection and
Bruno's CSV/Faker integrations are tested. Both npm and pnpm audits reported
zero vulnerabilities after these changes. Keep the tooling lock separate from
the web workspace so its large CLI tree does not ship with the app.

Install from the repository root:

```sh
npm ci --prefix tools/bruno --ignore-scripts --no-audit --no-fund
node --test tools/bruno/compatibility.test.cjs
npm audit --prefix tools/bruno --audit-level high
```

Run API checks from `tests/api` with the backend running:

- macOS: `../../tools/bruno/node_modules/.bin/bru run --env local`
- PowerShell: `& "../../tools/bruno/node_modules/.bin/bru.cmd" run --env local`

The public tunnel is ephemeral; start a fresh one when needed. Do not use an
old checkpoint URL. The CLI overrides are tooling-only; no product endpoint,
response, auth boundary or database migration changes here.

## Future updates and deferred migrations

Dependabot now assigns Gradle, web npm, Bruno npm and GitHub Actions to one
weekly `maintenance` multi-ecosystem group. This follows
[GitHub's grouping configuration](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/configuring-multi-ecosystem-updates).
The configuration takes effect after this PR merges. Security updates may
still be separate; repository alert settings are not disabled.

Explicit version exclusions prevent the known incompatible upgrades from
reopening repeatedly while allowing compatible updates. They are not permanent
security exceptions. Person One owns backend migrations; Person Two owns web
lint/tooling migrations; review these exclusions at the Phase 1 contract session
and whenever an advisory affects a retained version. Remove an exclusion only
with the migration and passing regression checks in the same reviewed PR.

- Boot/validator: migrate JSON configuration, error serialization and schema
  validation together, preserving strict scalar validation and response shapes.
- ESLint: wait for or migrate the Next/React plugins to the new rule API.
- TypeScript: require parser/linter support and a successful Next build; do not
  suppress lint failures to install the new compiler.
- Node typings: advance alongside the runtime, not independently.
- Bruno: remove overrides as upstream incorporates patched dependencies, after
  checking the audit and API/compatibility tests.

## Verification

Local combined verification passed: backend tests and Checkstyle, bootJar,
web lint/build and 21 production Playwright cases, four Bruno requests/four
script tests/11 assertions, and two Bruno dependency compatibility tests.
The replacement PR's checks are authoritative for hosted Windows, iOS,
PostgreSQL/PostGIS, OpenAPI, secret scanning and CodeQL results.

The original proposals are superseded by the replacement PR, including the
explicitly deferred versions above. Closing those proposals does not claim
that every proposed major upgrade was installed.
