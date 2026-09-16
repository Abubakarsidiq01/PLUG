# Staging deployment checklist

This checklist prepares the connected Phase 0 proof. It is not evidence of a deployed system.

1. Agree the AWS account, region, budget limit, HTTPS hostname, private subnets, and deployment owner.
2. Store Terraform state in encrypted, access-controlled remote storage with locking.
3. Review the database plan before applying it. Provision a runtime role without owner, superuser, or extension-management privileges.
4. Run migrations using the separate migration role. Confirm `PostGIS_Version()` and Flyway validation succeed.
5. Build `./dev bootJar`, deploy one application process behind an HTTPS ingress, and activate `staging`.
6. Supply database credentials through the secret store. Use JDBC `sslmode=verify-full` with the trusted database CA. Never use disabled certificate checks.
7. Configure `PLUG_JWT_ISSUER` and `PLUG_JWT_AUDIENCE` from the agreed identity provider. Request writes require `plug.requests.write` scope.
8. Bind the process to its private application interface using `PLUG_BIND_ADDRESS`. Do not expose the backend port directly to the Internet.
9. Add ingress request-size, connection, timeout, and rate limits. The application limiter is per process and uses the immediate peer address, so it is not a replacement for an ingress limit.
10. Probe `/actuator/health/readiness`, configure alarms for failed readiness, 5xx, latency, database connections, and restart frequency.
11. Run the app on a physical phone with the real HTTPS URL. Record success, network failure, invalid-response handling, build, screenshot, and correlation IDs in the tracker.

Required environment variables:

- `SPRING_PROFILES_ACTIVE=staging`
- `PLUG_BIND_ADDRESS`
- `PLUG_DATABASE_URL`, `PLUG_DATABASE_USER`, `PLUG_DATABASE_PASSWORD`
- `PLUG_MIGRATION_DATABASE_URL`, `PLUG_MIGRATION_DATABASE_USER`, `PLUG_MIGRATION_DATABASE_PASSWORD`
- `PLUG_JWT_ISSUER`, `PLUG_JWT_AUDIENCE`

Rollback by deploying the previous verified application artifact. Do not rewrite or delete applied migrations. Restore backups only through a separately approved recovery procedure.
