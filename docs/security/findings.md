# Security findings log

Every finding from any source — CI scan, ZAP, manual review, the audit prompt —
gets a row. A finding is closed by a fix or by a dated exception, never by
silence.

| ID | Date | Severity | Source | Finding | Owner | Status | Fix / exception | Expires |
|---|---|---|---|---|---|---|---|---|
| P0-H01 | 2026-09-20 | high | HTTP regression | Encoded API paths bypassed request-size and rate limits | person_one | fixed locally | Decode application paths before matching; real HTTP regression passes | — |
| P0-H02 | 2026-09-20 | medium | Browser regression | A forged cookie unlocked the admin placeholder; login-prefix paths bypassed the redirect | person_two | fixed locally | Fail closed until real sessions exist; exact login exemption; 15 browser cases pass | — |
| P0-H03 | 2026-09-20 | medium | Log capture regression | Raw unknown paths entered MDC; framework debug output exposed query text and precise coordinates | person_one | fixed locally | Redact MDC paths and request DTO diagnostic strings; captured-log tests pass | — |
| P0-H04 | 2026-09-20 | medium | Signed JWT regression | Missing audience caused a null-pointer error instead of token rejection | person_one | fixed locally | Validate absent audiences; signed-token regression passes | — |
| P0-H05 | 2026-09-20 | medium | Scanner configuration review | API collections and all JSON fixtures were excluded from secret scanning | person_one | fixed locally | Remove blanket allowlist; source snapshot including fixtures scans clean | — |
| P0-H06 | 2026-09-20 | medium | iOS source review and tests | Health-response size was checked only after the entire download was buffered | person_one | fixed locally | Stream with a 16 KiB cap and cancel task; iOS response tests pass | — |
| P0-H07 | 2026-09-20 | medium | Tunnel boundary review | Forwarded public requests could read operational health details | person_one | fixed locally | Deny forwarding headers on private probes; direct local checks preserved; live tunnel recheck pending | — |

Local fixes and test scope are recorded in
[the verification report](../testing/phase-0-hardening-2026-09-20.md).
GitHub CI, independent review and the live two-person gate are still pending.

## Exception rules

An accepted critical or high finding needs all four of:

1. A named owner
2. A written mitigation that reduces the risk now
3. An expiry date, no more than one phase away
4. Both people's agreement, recorded in the pull request

An exception without an expiry date is not an exception. It is a decision to
ship the problem permanently.
