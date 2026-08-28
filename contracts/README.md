# Contracts

`openapi.yaml` is the source of truth for routes, fields, casing, enums, errors, and examples.

1. Update OpenAPI and relevant examples.
2. Obtain review from both engineers.
3. Update provider tests and iOS decoding tests.
4. Merge backend and iOS changes in the same integration window.

Never silently patch only one side. IDs are opaque strings; time is ISO-8601 with timezone; future money fields use integer cents plus currency.
