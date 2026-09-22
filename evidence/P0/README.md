# Phase 0 verification evidence

## Current closeout — 22 September 2026

G0 was signed in PR #21 after the real joint public checkpoint; PRs #22 and #23
are merged. All seven workflow jobs passed on merged main `c855ca0`.
The earlier records below retain their original scope and dates.

- [Joint checkpoint](logs/connected-checkpoint-2026-09-22.log): actual phone and
  Windows participation, superseding the earlier public-test deferral.
- [Database resilience](logs/database-resilience-2026-09-22.md): real pool
  exhaustion, slow-query cancellation and recovery tests added at closeout.
- [Person Two setup record](../../docs/onboarding/person-two-setup-record.md):
  Node version and the clean 21/21 local browser run reported in PR #23.
- Person One confirmed on 22 September that both engineers agreed the existing
  Phase 0 API contract at 0.1.0. This records that confirmation, not a new GitHub
  review submitted on either person's behalf.

AWS remains deferred under ADR-004. ADR-005's local setup report follow-up is
carried into P1; the public checkpoint is complete. Phase 1 authentication has
not been implemented or tested. See `PROJECT_STATE.json` for the current state.

## Windows

The real Windows runner passed on source commit `16b9c57`:
[workflow 35558025459](https://github.com/Abubakarsidiq01/PLUG/actions/runs/35558025459).
It verified installation, web production build, 15 browser regressions, backend
startup, the local Bruno collection (4 requests, 4 script tests, 11 assertions)
and readable project state. Backend and Bruno logs are attached to that run.

The expanded 21-case suite subsequently passed on `aff4688` in both Web and
[Windows run 35558977515](https://github.com/Abubakarsidiq01/PLUG/actions/runs/35558977515).
All six workflows passed on that code revision. Subsequent evidence-only commits
retain the same application and test source; check PR #10 for their CI status.

This is hosted Windows verification. Person Two did not personally run it.
Her interactive Windows/Docker/WSL setup and own-machine public API run are
deferred to the start of Phase 1 by Person One under
[ADR-005](../../docs/decisions/ADR-005-phase0-windows-automation-handoff.md).

## Web accessibility and screenshots

Local production-build verification: 21 Playwright cases passed, including axe
4.13.0 scans of `/` and `/admin/login` at 360, 768 and 1280 CSS px. All six scans
have zero violations and zero incomplete checks. These files were generated
from that production run on the Mac; Windows has its own CI report.

- [`web/`](web/): six screenshots, exported at CSS pixel size.
- [`a11y/`](a11y/): the six complete axe result files.
- [`security/pnpm-audit-2026-09-20.json`](security/pnpm-audit-2026-09-20.json):
  workspace audit of 404 dependencies with zero reported vulnerabilities.

Automated axe results cover detectable issues on these two shell pages; they
are not a claim of a complete manual web accessibility audit or future screens.

## Physical iPhone

[`logs/device-hardening-checkpoint-2026-09-20.log`](logs/device-hardening-checkpoint-2026-09-20.log)
records the iPhone 13 Pro Max/iOS 26.6 success, matching phone/Xcode/backend
request ID, and Person One's reported offline recovery, largest-text and
VoiceOver results. The supplied screenshots are now recorded:

- [Offline error and Retry](ios/iphone-offline-2026-09-20.png) — source `IMG_4100.HEIC`.
- [Connected at enlarged text size](ios/iphone-connected-large-text-2026-09-20.png) — source `IMG_4101.HEIC`.
- [Scrolled request ID and Retry](ios/iphone-large-text-retry-2026-09-20.png) — source `IMG_4102.HEIC`.

These are full-resolution PNG conversions of the supplied HEIC files, with no
cropping or content edits. The last screenshot shows
`req_8f002dc8-d721-49b2-94bd-326714d7a76f`, matching a backend HTTP 200 at
22:38:34 America/Chicago. The Connected screenshot shows Wi-Fi; cellular
recovery and VoiceOver activation remain operator-reported checks.

The earlier device log and screenshot are preserved as historical evidence.

The current temporary tunnel also passed three public Bruno cases from the Mac
(200/202/400; 3 script tests and 8 assertions), and public readiness returned 401.
This does not claim a Windows public-tunnel run, a live two-person witness,
database-enabled staging, authenticated staging, or G0 sign-off.

## Review

See [PR #10](https://github.com/Abubakarsidiq01/PLUG/pull/10) for the final CI
revision and actual reviewer approval. G0 and contracts remain pending until
their actual approvals are recorded; no approval has been supplied on another
person's behalf.
