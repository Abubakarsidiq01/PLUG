# Runbook — A release is failing in production

**Owner:** Person One  ·  **Escalation:** both people

## Steps

1. Do not debug in production first. Roll back, then debug.
2. Try feature flags first — faster and less disruptive than a redeploy.
3. If flags are insufficient: ./infra/scripts/rollback.sh production
4. Verify with a real transaction, not a 200 from the health endpoint.
5. Confirm no migration ran that the previous version cannot tolerate. If one did, this is a data incident.
6. Tell testers, briefly and honestly.
7. Only then reproduce in staging and find the cause.
8. Write the incident note, including which test would have caught it.

## After

- Incident note in `docs/incidents/` the same day
- Any new risk added to `open_risks` in `PROJECT_STATE.json`
- If the drill in Phase 6 did not cover this, add it
