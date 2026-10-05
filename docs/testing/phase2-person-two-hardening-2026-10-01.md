# Phase 2 Person Two preparation and hardening

Person Two's P2.S1 fixtures and labelled dataset are now prepared against proposed
contract 0.3.0. Local checks pass. The contract remains proposed, `requests_v2`
remains off, and G2 is not signed. The user authorized this Person Two work on the
Mac; this is not independent Person Two sign-off or Windows evidence.

Source: PLUG Production Master Manual v3, §§7.1–7.2, 19.5–19.6 and 27.3,
`docs/phases/P2-TWO.md`, `PROJECT_STATE.json`, and `contracts/openapi.yaml`.
Work branch: `p2.s1-two-fixture-hardening`, based on the existing contract proposal.

## Findings addressed

- The success fixture still advertised Phase 0's 202/RECEIVED body. It now uses
  Phase 2's proposed 201 resource. All five operations have fixtures, including
  every documented HTTP response. The old live stub remains explicitly labelled
  in Bruno and covered by its original contract example.
- Unanswered drafts could expire or be canceled, but the proposal required a
  concrete category outside draft. The proposal now preserves null for those
  terminal outcomes; fixtures prevent inventing a category when closing a draft.
- Restricted-intent prose said there was no request ID while the shared error
  schema required one. The proposal now distinguishes a created resource ID
  (absent) from the error correlation ID (required).
- Schema-only checks allowed impossible progress, inappropriate seed labels,
  invalid offer timing and mismatched next actions. New QA assertions cover these
  invariants, with 11 deliberate corruptions proving the checks reject bad data.
- There was no labelled dataset. There are now 42 fixed-clock vectors spanning
  ambiguity, explicit input precedence, unsupported/restricted intent, input
  boundaries, provider failure and fallback expectations.
- The documented `typecheck` and `test:unit` commands did not exist. They now work;
  type checking generates Next route types first. The unit command delegates to
  the shared fixture/data checks and is documented as static validation.
- Playwright silently reused an existing localhost server, which could validate
  stale code. It now owns port 3100; an explicit `PLUG_WEB_URL` tests an existing
  deployment without launching an unrelated local server.
- Windows CI now runs the fixture/data suite and explicitly propagates install,
  fixture and build failures. Windows onboarding documents the required stable
  identity pepper and uses the lockfile. The P2 guide no longer points to a
  nonexistent abuse directory or claims the old Bruno requests test P2.
- Local dependencies were stale (Next 16.3.5 was installed against a 16.3.6 lock).
  Reinstalled from the lockfile. The new validator uses patched Ajv 8.18.0;
  the completed workspace audit reports no known vulnerabilities.

## Verification completed locally

| Check | Result |
|---|---|
| `pnpm test:contracts` | 127 passed; 68 response fixtures and 42 labelled inputs |
| `backend/./dev check bootJar` | 42 non-database tests passed; Checkstyle and boot JAR passed |
| `pnpm --filter @plug/web typecheck` | Passed |
| `pnpm --filter @plug/web lint` | Passed |
| `pnpm --filter @plug/web build` | Passed with locked Next 16.3.6 |
| `CI=true pnpm --filter @plug/web test:e2e --workers=3 --reporter=line` | 81 passed; Chromium/WebKit at 360, 768 and 1280 px |
| `node --test tools/bruno/compatibility.test.cjs` | 3 passed |
| Spectral 6.15.0, `--fail-severity warn` | No warnings or errors |
| `pnpm audit --audit-level moderate` | No known vulnerabilities |

The initial browser attempt hit a sandbox socket restriction. The successful run
used approved local-server access and a dedicated production server, not the old
interactive server. The backend run excluded database-tagged tests by its normal
configuration. No account data, signing configuration or existing iOS changes
were modified by this work.

## Remaining blueprint work

1. Both engineers review the contract amendments, fixtures and dataset labels,
   resolve the open product questions in PROJECT_STATE.json, and merge the
   contract proposal. No approval is inferred from the user authorizing coding.
2. Person One implements the adapter, state machine, migrations and request API
   behind `requests_v2`. Run the dataset with its fixed clock and injected provider
   conditions. Test all legal/illegal transitions, concurrent cancellation,
   replay and ownership, audit/no outreach, request sizes and rate limits.
3. Person Two completes P2.S2 live Bruno coverage and P2.S6 abuse runs against that
   implementation. Static fixtures cannot demonstrate those behaviors. Review
   the actual Figma frames for P2.S3; no linked design file was available here.
4. P2.S4's inspector stays optional and requires real authorized staging data.
   P2.S5's exact parser grammar must be frozen with the implementation; the
   dataset is review input, not a claim that those phrases work today.
5. Run the connected staging/device checkpoint, collect correlation IDs and
   failure/accessibility evidence, and obtain both G2 signatures.

The schema intentionally leaves some service rules in prose: nonblank text,
control characters, USD-only currency, budget/currency pairing and the relative
seven-day horizon. The dataset marks those inputs schema-valid but expects service
rejection. Verify that rejection in the future backend; do not confuse schema
acceptance with product acceptance. The 7-day horizon and 24-hour idempotency
retention remain proposals, and the default search radius stays server-configured.

Fixture/data validation is wired into Linux and Windows CI, but neither remote CI
nor execution on Person Two's Windows machine was claimed in this local run.
