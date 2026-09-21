# PLUG roadmap

Eight phases. Each ends with a gate. A gate is signed only when a connected
demonstration has been run and its evidence attached.

Find the last signed gate in `PROJECT_STATE.json`. The next phase is where you
are.

| Phase | Name | Gate | Duration | Person One (Mac) | Person Two (Windows) |
|---|---|---|---|---|---|
| P0 | Foundations | G0 | ~1 wk | Monorepo, Spring Boot skeleton, health, CI | Windows clone proof, web shell, Playwright, Bruno, fixtures |
| P1 | Identity and consent | G1 | ~1 wk | Apple, phone OTP, guest, sessions | Legal pages, admin shell, auth test suites |
| P2 | Ask, parse, clarify, results | G2 | ~1.5 wk | Intent adapter, state machine, progress | Intent dataset, contract tests, design review |
| P3 | Supplier, SMS, offers | G3 | ~2 wk | Twilio, fan-out, parsing, reservation | Supplier copy and web UI, messaging monitor |
| P4 | NOW, Live Checks, Scout | G4 | ~2 wk | Truth labels, scouts, credit ledger | NOW monitor, label fixtures, abuse cases |
| P5 | Trust, safety, admin | G5 | ~1.5 wk | RBAC, audit, reports, deletion | Full admin console, RBAC tests, legal pages |
| P6 | Beta hardening | G6 | ~1.5 wk | Load, restore, rollback, TestFlight | E2E, Lighthouse, SEO, ZAP, copy audit |
| P7 | One-zone beta launch | G7 | ongoing | Production ops, metrics, incidents | Tester comms, daily smoke, triage |

## Gate signature format

```
G3 PASSED 2026-04-25
  evidence:    evidence/P3/  (18 screenshots, 2 failure recordings, CI run #611)
  request_id:  req_01H9AB3M2K  (visible in ios.log:2211 and api.log:88431)
  signed:      person_one ✓   person_two ✓
  open:        supplier fan-out cap not load-tested above 40 req/min
```

A gate line with no request ID, or with only one signature, is not a gate.

## Per-phase READMEs

`docs/phases/P0-ONE.md` … `docs/phases/P7-TWO.md` — one per person per phase.
