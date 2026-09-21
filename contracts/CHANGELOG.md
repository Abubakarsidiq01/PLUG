# Contract changelog

Every change to `/contracts` gets an entry. Both approvals required on the pull
request. Format:

```
### <version> — <date> — additive | BREAKING — <state token>
<what changed, in one or two sentences>
Fixtures updated: <paths>
Migration note: <none | what must happen, in what order>
Rollback: <what turning the flag off does>
```

### 0.1.0 — unreleased — P0
Initial contract: `GET /health`, `GET /health/ready`, `POST /v1/requests` stub,
and the shared error envelope.
Fixtures: `fixtures/requests.create/{success,validation-error}.json`
Migration note: none.
