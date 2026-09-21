# Runbook — The queue is growing or the DLQ has entries

**Owner:** Person One  ·  **Escalation:** both people

## Steps

1. Check the oldest message age and the DLQ count first — they say whether this is slow or broken.
2. If workers are dying: read the error. A poison message in a loop looks like a backlog.
3. If the downstream provider is failing, go to provider-outage.md instead.
4. Do not increase concurrency to catch up. Bounded concurrency is protecting the database.
5. Inspect DLQ messages individually. Replay only after confirming idempotency handles a replay.
6. If messages are unrecoverable, record which and what user impact that has.
7. Write the incident note, including whether the alert threshold gave enough warning.

## After

- Incident note in `docs/incidents/` the same day
- Any new risk added to `open_risks` in `PROJECT_STATE.json`
- If the drill in Phase 6 did not cover this, add it
