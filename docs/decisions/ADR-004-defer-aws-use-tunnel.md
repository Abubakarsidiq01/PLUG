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
