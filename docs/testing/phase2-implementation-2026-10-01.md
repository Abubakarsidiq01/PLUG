# Phase 2 implementation — local verification and phone run

Branch `p2.s2-all-request-flow`, against proposed contract 0.3.0 with `requests_v2` on only
in isolated runtimes. The owner authorized all Phase 2 work across both lanes on this Mac.
No engineer approval, Windows run or G2 signature is inferred from that authorization.

## One-command automation

| Command | What it does |
|---|---|
| `sh tools/phase2-verify-all.sh` | Every automated check below, against disposable data, in about 35 minutes |
| `sh tools/run-phase2-phone.sh` | Database, isolated backend, HTTPS tunnel, signed build installed and launched on the paired iPhone |
| `sh tools/run-phase2-ui-evidence.sh` | Simulator screenshots of every request state at default and largest Dynamic Type |

Details: `docs/runbooks/phase2-local.md`.

## Results (one uninterrupted `phase2-verify-all.sh` run, 2026-10-01)

| Check | Result |
|---|---|
| Backend unit tests, Checkstyle, boot JAR | Passed |
| Backend database tests (PostGIS), incl. 7 request-flow tests | 77 passed |
| Contract, fixture and labelled-dataset checks | 132 passed |
| Web typecheck and lint | Passed |
| Spectral 6.15.0, `--fail-severity warn` | No findings |
| Live API suite, fresh isolated backend | 863 checks passed, 0 failed, 246 exchanges — `evidence/P2/security/phase2-live-2026-10-01.json` |
| Phase 2 Bruno collection | 39/39 requests, 51 tests, 63 assertions |
| iOS unit tests incl. live sign-in against the fresh backend | 58 executed, 0 failures |
| iOS request screenshot UI tests | 2 passed; 18 screenshots in `evidence/P2/simulator/2026-10-01/` |

The simulator screenshots come from the synthetic fixture server. They show the required
states render without horizontal overflow at the largest accessibility size; they are not
the physical-device evidence G2 requires.

## Defects found and fixed

- **Request tests failed after 20:15 UTC.** `RequestV2Test` pinned every `Clock` bean to
  20:00 UTC, so sessions were issued already expired against the database's `now()` and all
  seven request tests returned 401. The request module now takes its own `RequestClock`;
  identity time is untouched and production behaviour is unchanged.
- **UI tests could not sign in when built unsigned.** Without a keychain entitlement the
  session cannot be stored. The evidence script uses normal simulator signing.
- **UI test text entry.** The app keeps the previous request's words after "Start a new
  request"; the test's deletes landed at the start of the field. The test now taps the end.
- **UI test scrolling.** At the largest text size the request field is below the fold;
  `reveal` now scrolls both ways and waits for a control to have a frame while progress
  re-renders.
- **Simulator location.** The demo-zone location is pinned, and the test asks again when
  the simulator's one-shot location answers "unknown" (the app correctly offers the
  address path in that case).

## Environment repairs (no code change)

- Stale backends on 18080/18082 were still running from a JAR replaced by later builds;
  they were stopped and the phone backend relaunched from an immutable snapshot.
- The Phase 1 backend on 8080 returned 500 for guest sign-in: its database container
  `infra-postgres-1` had stopped, and its classes had been rebuilt under it. The container
  was started (same volume, accounts preserved) and the backend restarted with
  `tools/run-phase1-local.sh`; guest sign-in returns 201.

## Phone

`tools/run-phase2-phone.sh` built, signed, installed and launched PLUG on the paired iPhone
13 Pro Max against the isolated backend through a Quick Tunnel. The backend log shows the
phone's guest sign-in (201) and `GET /v1/me` (200). Screenshots are taken by the owner.

## Still required for G2 (not claimed)

- Physical-device screenshots of every state at default and largest text, and a VoiceOver
  walkthrough of the primary flow (`evidence/P2/ios/`, `evidence/P2/a11y/`)
- A recorded deliberate failure and recovery on the device (`evidence/P2/failures/`)
- Figma review (no linked design file), Person Two's run on Windows
- Contract 0.3.0 approval by both engineers, the two-person connected checkpoint on
  staging with a correlation ID in both logs, and both G2 signatures
