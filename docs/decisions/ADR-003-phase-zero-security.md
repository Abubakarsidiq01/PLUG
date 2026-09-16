# ADR-003: Keep local development private and protect staging writes

Status: Accepted for implementation; shared contract review pending

## Decision

Local development binds to loopback and permits only health checks and the Phase 0 request stub. Staging validates signed JWTs, issuer, expiry, audience, and write scope. Sessions, form login, and Basic authentication are not enabled. CSRF is ignored only on the explicit bearer-header mutation route; cookie-based authentication must revisit this decision.

## Limits

Request bodies are limited to 16 KiB, JSON ambiguity is rejected, connection pools and request queues are bounded, and request-rate tracking has a fixed maximum size. Responses do not expose internal errors or database details. Logs omit queries, coordinates, tokens, and unknown paths.

## What this does not promise

This is not a claim of complete security or measured capacity. Staging still needs an HTTPS ingress, secret rotation, account access controls, backup recovery testing, dependency review, and load testing. Phase 1 must define user identity and authorization; the Phase 0 write scope is not object-level authorization for future features.
