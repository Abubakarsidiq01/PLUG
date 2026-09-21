# Runbook — Auth or OTP endpoints are under abuse

**Owner:** Person One  ·  **Escalation:** both people

## Steps

1. Confirm the pattern: per-IP, per-phone, or distributed across both.
2. Check that the layered limits are firing. If only one is, the others are misconfigured.
3. Confirm healthy authenticated traffic is still being served — the limits must not shed everyone.
4. If distributed: tighten the WAF rule for the pattern, not the global limit.
5. Check whether any account was actually compromised. Revoke those session chains.
6. Do not lower the limits permanently without measuring the false-block rate.
7. Write the incident note, including the cost in provider spend if OTPs were sent.

## After

- Incident note in `docs/incidents/` the same day
- Any new risk added to `open_risks` in `PROJECT_STATE.json`
- If the drill in Phase 6 did not cover this, add it
