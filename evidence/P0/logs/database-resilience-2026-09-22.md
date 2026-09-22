# Database failure and recovery verification

Executed 22 September 2026 on the Phase 0 closeout working changes based on
merged main `c855ca0`. This is local test evidence; the closeout PR must also
pass hosted CI before merge.

Environment: Java 21, Gradle 9.7.1, isolated `postgis/postgis:16-3.5` container
published only on `127.0.0.1:25432`. The shared development database was untouched.
The test database used disposable synthetic credentials and was removed afterward.

Command from `backend`, with the test database URL/password supplied through
environment variables: `./dev test databaseTest check --console=plain`.
Result: BUILD SUCCESSFUL; unit tests, three database tests and Checkstyle passed.

The database suite verifies:

1. Flyway migration validation and a real PostGIS query.
2. Holding every connection in the configured Hikari pool makes readiness return
   503 within 12 seconds, while public liveness stays 200. Releasing connections
   restores readiness to 200. The production acquisition timeout remains 3 seconds.
3. PostgreSQL cancels `pg_sleep(15)` with SQLSTATE `57014` before 10 seconds;
   a subsequent query on the same connection and readiness both succeed.
   The connection initialization now sets a 5-second server-side statement timeout.

JUnit XML and HTML reports are generated in `backend/build/test-results` and
`backend/build/reports/tests`; the existing backend CI uploads those reports.
This validates bounded database failure handling, not a throughput benchmark,
cloud failover, or an end-to-end deadline for every future HTTP operation.
