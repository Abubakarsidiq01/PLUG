# PLUG threat model — v1

Reviewed at every phase gate. Update it when a trust boundary or a data class
changes, before the change ships.

## Trust boundaries

Treat as untrusted until validated server-side:

- The iOS app and anything it sends
- The browser (public site and admin console)
- Inbound SMS payloads and Twilio webhooks
- Model and provider output
- Admin inputs
- Every third-party response

## Data classification

| Class | Examples | Handling |
|---|---|---|
| Public | Marketing copy, supported categories | No restriction |
| Internal | Aggregate metrics, feature flags | Staff only |
| Sensitive | Phone numbers, coarse location, supplier consent records | Encrypted, masked in UI and logs, access audited |
| Restricted | Auth and session material, precise location, moderation evidence | Never logged, never exported, access audited, minimal retention |

## Top risks, and the control that addresses each

| Risk | Control | Section |
|---|---|---|
| BOLA/IDOR — reading another user's request | Resource-level authorization on every read and write; 404 rather than 403 | §19.4 |
| Texting a business that never consented | Explicit recorded consent, eligibility query, suppression at send time | §27.4 |
| Duplicate offer from a retried webhook | Signature, replay claim on MessageSid, unique constraint | §19.8 |
| A fabricated price or availability | Deterministic parsing; model output validated; Confirmed only from supplier event | §19.5, §19.6 |
| NOW becoming a surveillance tool | Approved public places, structured answers only, hidden requester identity, caps | §25.6 |
| Secret leaking to the client | Environment schema validation; CI greps the built bundle | §21.5, §23.2 |
| Credential in a log | Structured logging rules plus a redaction appender plus a CI check | §19.9 |
| One account exhausting capacity | Per-route, per-user and per-IP rate limits; queue backpressure | §25.8 |
| Unrecoverable data loss | PITR backups plus a proven restore drill | §19.10, §27.7 |
| Bad deploy with no way back | Expand-and-contract migrations, feature flags, rehearsed rollback | §23.4 |

## Review log

| Date | Phase | Changes | Reviewed by |
|---|---|---|---|
| | | Initial model written | |
