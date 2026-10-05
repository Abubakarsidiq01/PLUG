# Phase 2 admin contract review

Status: read routes implemented and approved by Person One on 2026-10-05 as a 0.5.0 amendment
(`contracts/CHANGELOG.md`); frozen when Person Two approves the pull request. The staff
sign-in path and the web inspector remain open.
Manual v4 P2-TWO.S12 requires an admin view of skills and recent classification
decisions. The current contract contains no admin read routes, and Phase 1 issues
no admin sessions. The existing `/admin` rejection must remain until both the
read contract and the staff session path are approved and tested.

## Proposed review scope

- Vocabulary: read the canonical vocabulary version, tag, display name, synonyms
  and licence requirement. No browser-side copy of the classification rules.
- Recent decisions: ask ID, created time, current ask type or awaiting
  clarification, and resolved controlled skill tags. Label these as current
  decisions: `asks` does not currently retain the original classification history.
- Vocabulary gaps: term, seen count and first/last seen timestamps. Treat terms
  as user content; redact before display and never include them in page analytics.
- Refusals: rule identifier and timestamp from existing audit events, without
  exposing the user's raw prompt, coordinates or identity tokens.

Agree route names, schemas, generated enums, cursor pagination, maximum page size,
date filters and error fixtures in `contracts/openapi.yaml` before implementation.
Do not imply a model confidence score or model reasoning: neither is a supported
display field. Decide separately whether a wrong-classification investigation
needs a tightly controlled raw-text access route with a recorded purpose.

## Access and validation

Use the existing `AdminStepUpAuthorization.required()` boundary: server-resolved
admin scope **and** a verified second factor. Document how real staff acquire and
revoke that session; a mock principal proves the authorization predicate only.
Never mint admin capability from a cookie name, request header or client role.

Before enabling the view, verify anonymous, guest, member, forged-role,
admin-without-MFA, expired/revoked-admin and valid-admin cases; validate pagination
and response schemas, audit access, and prevent caching of protected results.
The UI must cover loading, empty, denied, offline, error and populated states
using generated response types, with no duplicate classifier in JavaScript.

Acceptance: both engineers approve the contract; a real authorized staging
session reads the same vocabulary and decisions as the API; denied-role and
redaction tests pass; the web design/accessibility gate is recorded. Until then,
P2-TWO.S12 and G2 remain open.
