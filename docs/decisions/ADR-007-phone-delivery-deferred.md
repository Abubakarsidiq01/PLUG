# ADR-007: Phone verification ships without a delivery channel until Phase 3

- Status: Accepted; delivery scope amended 2026-09-26
- Date: 2026-09-22

## Decision

Phase 1 implements the whole phone-verification mechanism — challenge creation,
expiry, the attempt limit, the three layered rate limits, constant-time
comparison and the audit events — behind a `PhoneCodeSender` interface with no
production implementation.

`plug.identity.phone-delivery` is `none` in every environment, including
staging. `POST /v1/auth/phone/start` answers `503 dependency_unavailable` and
names the paths that do work: Sign in with Apple, or continue as a guest.

A `development` option writes codes to a file under `build/`. It refuses to
construct unless `plug.environment` is `local`.

## Why

Twilio is Phase 3 work (manual.docx §27.4). Wiring it a phase early would mean
a provider account, a webhook URL a Quick Tunnel cannot keep stable (ADR-004)
and real message charges, none of which Phase 1 is judged on.

The alternative — returning a challenge for a message that will never arrive —
is the dishonest option. Someone would sit waiting for a code that does not
exist, and the screen would have no way to tell them why.

No code is ever written to the application log, in any environment. §19.9 lists
one-time codes alongside tokens and phone numbers, and a developer convenience
is not a reason to make an exception; `AuthLoggingTest` fails the build if one
appears.

## Consequences

- The phone path is complete and tested but not usable by a real person until
  Phase 3. `GuestAndUpgradeTest` and `PhoneVerificationTest` exercise it through
  a recording sender that stands in for the provider.
- G1's abuse suite can cover Apple, guest, session and authorization cases
  against real staging. The phone brute-force cases are proved by the automated
  tests rather than against staging, and that limitation is recorded with the
  gate rather than glossed over.
- Phase 3 implements `PhoneCodeSender` with Twilio and changes one configuration
  value. Nothing above the interface has to move.

## Amendment — 2026-09-26

The owner requested real phone OTP during Phase 1. PR #27 adds an optional
Twilio implementation of `PhoneCodeSender`, configured with either a Messaging
Service SID or a Twilio-owned sender number. This supersedes the original
no-production-implementation decision above; two-way SMS and iMessage remain
later-phase work. Outbound OTP does not require a public inbound webhook.

Delivery remains `none` by default. Missing or disabled delivery returns
`503 dependency_unavailable`; no real SMS delivery is claimed until sender
configuration and a physical-device receipt test succeed. Development code
files remain local-only with restricted permissions.
