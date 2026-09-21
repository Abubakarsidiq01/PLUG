# ADR-004: Defer AWS staging; use a Cloudflare Quick Tunnel for the Phase 0 checkpoint

- Status: Accepted
- Date: 2026-09-17

## Decision

Phase 0's exit criterion (manual.docx §27.1) is "a real HTTP call to real
staging," not specifically AWS. Budget is not available right now for any
cloud spend, including the near-$0/month minimal-cost AWS design documented
in `docs/runbooks/aws-staging-setup.md`. Rather than block the phase, "real
staging" for the Phase 0 connected checkpoint is a `cloudflared` Quick Tunnel
(`cloudflared tunnel --url http://localhost:8080`) pointed at the backend
running locally — a genuine public HTTPS URL, reachable from a physical
iPhone over cellular data and from Person Two's machine, at zero cost and no
account signup.

## Consequences

- The "staging" environment for G0 is temporary and tied to whichever machine
  runs the tunnel — it dies when that terminal closes, and is not a
  standing environment either engineer can rely on being up.
- `PROJECT_STATE.json.environments.staging` will record a live tunnel URL only
  while a connected-checkpoint session is running, not a permanent value.
- `docs/runbooks/aws-staging-setup.md` remains the plan for when real cloud
  infrastructure is actually needed — no later than Phase 3 (Twilio requires a
  stable webhook URL, which a Quick Tunnel cannot provide since the hostname
  changes every time it restarts).
- G0 sign-off should note this as a known limitation: the checkpoint proves
  the communication path works, not that a durable staging environment exists.

## Checkpoint safety and API tests

Use synthetic request data only. The tunnel forwards the local Phase 0
validation stub; it does not activate the `staging` Spring profile or prove
JWT authentication, cloud isolation, or durable staging. Do not use this
unauthenticated mode for future persistent writes or provider integrations.

Keep the backend bound to `127.0.0.1` and stop the tunnel when the session ends.
The backend denies forwarded access to `/health/ready` and Actuator probes;
check readiness directly from Person One's machine. Forwarded headers are
only a denial signal, not trusted client identity. Keep
`server.forward-headers-strategy=none`; cloud ingress still needs private
network/probe rules when it is introduced.

From the repository root, both machines can use these commands (substitute
the current tunnel URL; do not commit a temporary URL):

```text
cd tests/api
bru run health.bru requests-create-success.bru requests-create-validation-error.bru --env local --env-var baseUrl=https://YOUR-CURRENT-TUNNEL.trycloudflare.com
```

Run the full collection locally with `bru run --env local` from `tests/api`.
`health-ready.bru` belongs to that direct local check, not the public tunnel
run. Public access to `/health/ready` must be rejected. The signed-token
`staging` profile remains separate and still requires its configured issuer,
audience and write scope.
