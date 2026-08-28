# ADR-002: Use OpenAPI as the shared contract

- Status: Accepted
- Date: 2026-08-28

## Decision

`contracts/openapi.yaml` defines routes, authentication, schemas, casing, enums, and errors. Examples and consumer/provider checks change with it.

## Consequences

Backend and iOS can work independently against reviewed fixtures. Breaking changes require versioning or a coordinated release and approvals from both engineers.
