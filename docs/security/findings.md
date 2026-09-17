# Security findings log

Every finding from any source — CI scan, ZAP, manual review, the audit prompt —
gets a row. A finding is closed by a fix or by a dated exception, never by
silence.

| ID | Date | Severity | Source | Finding | Owner | Status | Fix / exception | Expires |
|---|---|---|---|---|---|---|---|---|
| | | | | | | | | |

## Exception rules

An accepted critical or high finding needs all four of:

1. A named owner
2. A written mitigation that reduces the risk now
3. An expiry date, no more than one phase away
4. Both people's agreement, recorded in the pull request

An exception without an expiry date is not an exception. It is a decision to
ship the problem permanently.
