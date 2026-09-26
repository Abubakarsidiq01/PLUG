# ADR-006: Opaque, server-stored session tokens rather than signed JWTs

- Status: Accepted
- Date: 2026-09-22

## Decision

PLUG's own access and refresh tokens are opaque random values. The server stores
a SHA-256 hash of each one in `sessions` and resolves it on every request. They
are not JWTs and carry no claims.

Access tokens live 15 minutes. Refresh tokens rotate on every use and live 30
days for a verified account and 7 days for a guest. Presenting a refresh token
that has already been rotated revokes the whole chain.

This applies only to tokens PLUG issues. `POST /v1/requests` keeps the
externally issued JWT that Phase 0 froze, on its own filter chain, and Apple's
identity token is still verified as a signed JWT against Apple's published keys.

## Why

Phase 1's outcome sentence says logout revokes the session server-side, and
§25.2 requires session invalidation after any account-security change. A signed
JWT cannot be revoked; it can only be allowed to expire, or be checked against a
denylist on every request — which is a database read per request, the same cost
as an opaque token, with a second mechanism to keep correct.

With one modular monolith and no second service that needs to verify a token
without asking us, stateless verification buys nothing here. It would also mean
a signing key to hold, rotate and eventually leak.

## Consequences

- Every authenticated request does one indexed read on `sessions`, and one
  write to `last_used_at`. That is measured before it is optimised; at this
  scale it is not the bottleneck, and if it becomes one the answer is a cache
  in front of the read, not claims the server cannot withdraw.
- Revocation is immediate and total: logout, a lost device, a detected replay
  and account deletion all take effect on the next request.
- There is no offline verification. Anything that needs to check a PLUG session
  has to reach the API, which is true of everything V1 ships.
- A token found in a log or a crash report can be revoked by its prefix
  (`pat_`, `prt_`) being recognisable, without decoding it.
- If a second service ever needs to verify a session independently, that is a
  new decision and a new ADR, not a quiet change to this one.
