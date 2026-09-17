# Runbook — Data loss or corruption requiring a restore

**Owner:** Person One  ·  **Escalation:** both people

## Steps

1. Stop writes: set the maintenance flag, which returns a controlled 503 on mutations.
2. Identify the last known-good point in time. Do not guess — check the audit log.
3. Restore to a NEW instance. Never restore over the live one.
4. Verify the restored data: row counts, the latest audit event, a known request end to end.
5. Repoint the application, then run the smoke script before removing the maintenance flag.
6. Record the ACTUAL RPO and RTO achieved, not the target.
7. Reconcile anything written between the restore point and the incident, by hand, audited.
8. Write the incident note, including why the drill numbers differed from reality.

## After

- Incident note in `docs/incidents/` the same day
- Any new risk added to `open_risks` in `PROJECT_STATE.json`
- If the drill in Phase 6 did not cover this, add it
