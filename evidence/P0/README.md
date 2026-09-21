# Phase 0 verification evidence

## Windows

The real Windows runner passed on source commit `16b9c57`:
[workflow 35558025459](https://github.com/Abubakarsidiq01/PLUG/actions/runs/35558025459).
It verified installation, web production build, 15 browser regressions, backend
startup, the local Bruno collection (4 requests, 4 script tests, 11 assertions)
and readable project state. Backend and Bruno logs are attached to that run.

The subsequent accessibility change expands browser coverage to 21 cases. Both
Web and Windows workflows execute it and attach screenshots and axe results in
their Playwright reports. The final PR checks must pass on that later revision.

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
VoiceOver results. Phone success/failure screenshots are still pending.
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
