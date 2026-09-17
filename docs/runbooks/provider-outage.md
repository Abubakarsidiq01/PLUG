# Runbook — A third-party provider (Twilio, model, Places) is failing or hanging

**Owner:** Person One  ·  **Escalation:** both people

## Steps

1. Confirm it is the provider: check the circuit-breaker state and the provider status page.
2. Check the alert that fired and the affected request volume in the last 15 minutes.
3. Verify the degradation path is working: are users seeing a recoverable state or an error screen?
4. If the circuit is not opening, that is a second incident — check the timeout configuration.
5. For Twilio: confirm queued messages are being held, not dropped. Check DLQ depth.
6. For the model provider: confirm the deterministic clarification fallback is serving.
7. Post a short status note for testers if the outage exceeds 15 minutes.
8. When the provider recovers: verify the queue drains without duplicating anything.
9. Write the incident note the same day. Include duration, user impact and what the drill missed.

## After

- Incident note in `docs/incidents/` the same day
- Any new risk added to `open_risks` in `PROJECT_STATE.json`
- If the drill in Phase 6 did not cover this, add it
