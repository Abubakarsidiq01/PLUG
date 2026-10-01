# Isolated Phase 2 verification

The request feature defaults off. Use a separate local database and API process
to exercise it while preserving existing Phase 1 app accounts. These commands use
disposable test credentials, never production secrets. No real supplier outreach
or paid provider is enabled by this setup.

Create a disposable PostGIS instance once:

```sh
docker run --detach --rm --name plug-phase2-validation --platform linux/amd64 \
  -e POSTGRES_DB=plug_phase2_tests -e POSTGRES_USER=plug \
  -e POSTGRES_PASSWORD=phase2-local-validation-only \
  -p 127.0.0.1:55433:5432 postgis/postgis:16-3.5
docker exec plug-phase2-validation pg_isready -U plug -d plug_phase2_tests
# Run createdb after pg_isready reports accepting connections.
docker exec plug-phase2-validation createdb -U plug plug_phase2_live
```

Backend database tests truncate identity data. Point them only at the test database:

```sh
PLUG_DATABASE_URL=jdbc:postgresql://127.0.0.1:55433/plug_phase2_tests \
PLUG_DATABASE_USER=plug \
PLUG_DATABASE_PASSWORD=phase2-local-validation-only \
PLUG_IDENTITY_PEPPER=phase2-local-test-pepper-not-for-real-use \
./backend/dev check databaseTest bootJar
```

Run the live app/QA backend in a separate terminal:

```sh
sh tools/run-phase2-local.sh
```

It binds `127.0.0.1:18080`, uses `plug_phase2_live`, enables
`PLUG_REQUESTS_V2_ENABLED`, and leaves the existing port 8080 backend untouched.
It builds once and launches an immutable temporary JAR snapshot. Do not run a
long-lived phone backend directly from `backend/build/libs`: another build can
replace that JAR while Java is lazily loading classes, breaking active requests.
It deliberately does not load `.env.local` or provider secrets. The iOS simulator
can use `PLUG_API_URL=http://127.0.0.1:18080`. A physical device needs a reachable
HTTPS URL for this same port; the temporary tunnel remains local development
under ADR-004, not a dedicated staging deployment.

PowerShell users can create the same container/databases with one-line Docker
commands, export the four `PLUG_DATABASE_*` / `PLUG_IDENTITY_PEPPER` variables,
set `$env:PLUG_REQUESTS_V2_ENABLED = "true"`, and run
`backend\gradlew.bat -p backend bootRun --args="--spring.profiles.active=db --server.port=18080"`.
Use `plug_phase2_tests` only for `databaseTest`, and `plug_phase2_live` for the app.

Stop the live backend with Ctrl+C when finished. `docker stop plug-phase2-validation`
removes both disposable databases because the container was created with `--rm`.
Do not stop it until evidence and any wanted test sessions have been saved.

## One-command phone run and full verification

`sh tools/run-phase2-phone.sh` does everything above for a physical device: starts the
disposable PostGIS container and `plug_phase2_live`, launches the isolated requests_v2
backend on port 18080 from a JAR snapshot, opens a Quick Tunnel, writes the tunnel URL and
`PLUG_REQUESTS_V2_ENABLED = YES` into `ios/Plug/Resources/Local.xcconfig`, waits for the
paired iPhone, then builds, installs and launches a signed Debug build. Control-C stops the
backend and tunnel and sets the flag back to `NO`. On the phone, continue as guest; seeded
results exist only in the synthetic Ruston, LA zone, so elsewhere type a Ruston address.

`sh tools/phase2-verify-all.sh` runs every automated check against disposable data: backend
unit and database tests, contract/fixture/dataset checks, web typecheck and lint, Spectral,
the live API suite and Bruno against a fresh backend, iOS unit tests (including live sign-in
against that backend) and, through `tools/run-phase2-ui-evidence.sh`, simulator screenshots
of every request state at default and largest Dynamic Type in `evidence/P2/simulator/`.
UI tests must be simulator-signed: an unsigned build has no keychain entitlement, so guest
sign-in fails before any request screen. The simulator location is pinned to the demo zone.

Do not run a backend build while the Phase 1 `tools/run-phase1-local.sh` server is up: it
runs from `backend/build/classes`, and a rebuild under it produces 500s until it restarts.
