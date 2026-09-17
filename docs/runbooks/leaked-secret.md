# Runbook — A credential has been exposed in a commit, log, screenshot or message

**Owner:** Person One  ·  **Escalation:** both people

## Steps

1. ROTATE FIRST. Investigate second. The old value is compromised the moment it is exposed.
2. Rotate in Secrets Manager, then redeploy anything holding the old value.
3. Revoke at the provider: Twilio auth token, model key, AWS key, JWT signing key.
4. If a JWT signing key: all sessions are invalid. Force re-authentication and tell testers.
5. Search the full Git history, not just recent commits. Scrubbing history requires a force push and both people.
6. Check provider logs for use of the credential between exposure and rotation.
7. Add a detection rule so this shape of secret is caught next time.
8. Write the incident note. Include how it was exposed, not just that it was.

## After

- Incident note in `docs/incidents/` the same day
- Any new risk added to `open_risks` in `PROJECT_STATE.json`
- If the drill in Phase 6 did not cover this, add it
