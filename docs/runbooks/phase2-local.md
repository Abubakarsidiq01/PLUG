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
It loads only an optional `ANTHROPIC_API_KEY` from the documented local files; no identity-provider credentials are sourced. The iOS simulator
can use `PLUG_API_URL=http://127.0.0.1:18080`. A physical device uses the private paired connection described below. This is a Debug-only local preview, not a dedicated staging deployment.

PowerShell users can create the same container/databases with one-line Docker
commands, export the four `PLUG_DATABASE_*` / `PLUG_IDENTITY_PEPPER` variables,
set `$env:PLUG_REQUESTS_V2_ENABLED = "true"`, and run
`backend\gradlew.bat -p backend bootRun --args="--spring.profiles.active=db --server.port=18080"`.
Use `plug_phase2_tests` only for `databaseTest`, and `plug_phase2_live` for the app.

Stop the live backend with Ctrl+C when finished. `docker stop plug-phase2-validation`
removes both disposable databases because the container was created with `--rm`.
Do not stop it until evidence and any wanted test sessions have been saved.

## One-command phone run and full verification

`sh tools/run-phase2-phone.sh` prepares `plug_phase2_live`, launches the isolated
backend, discovers the paired iPhone's private IPv6 interface, holds the connection,
and relays only that phone to the loopback backend. It builds, installs and launches
a signed Debug app. It never opens a public tunnel or a Wi-Fi wildcard listener.
It writes the current private address and Phase 2 flag into ignored `Local.xcconfig`.
Keep the phone connected and unlocked during installation. Re-run after reconnecting
because the private address may change. Control-C stops only processes it started;
existing occupied ports fail clearly rather than stopping someone else's server.

The phone runner needs a valid development profile for the app. Physical UI automation
also needs a separate profile for `com.abubakarsidiq01.plug.app101.uitests.xctrunner`:
select the same development team for PlugUITests in Xcode, enable automatic signing,
and enable UI Automation under Settings → Developer on the phone. A working app profile
alone does not establish that the test runner can be signed.

For physical state screenshots, hold a paired connection with `devicectl device
notification observe`, obtain `tunnelIPAddress` from `devicectl device info details`,
and find the Mac address in the same `/64` from `ifconfig`. Then run:

```sh
PLUG_PAIRED_HOST='<Mac paired IPv6 address>' \
PLUG_PAIRED_PEER='<iPhone paired IPv6 address>' \
sh tools/run-phase2-device-evidence.sh
```

The fixture relay uses port 18087 and only accepts the paired phone and Mac address.
Screenshots are real-device renders of synthetic states, labelled separately from live
API and joint checkpoint evidence. Reinstall the live-backend build afterward. VoiceOver
and the independent greyscale review still require their actual walkthroughs.

`sh tools/phase2-verify-all.sh` runs every automated check against disposable data: backend
unit and database tests, contract/fixture/dataset checks, web typecheck and lint, Spectral,
the live API suite and Bruno against a fresh backend, iOS unit tests (including live sign-in
against that backend) and, through `tools/run-phase2-ui-evidence.sh`, simulator screenshots
of every request state at default and largest Dynamic Type in `evidence/P2/simulator/`.
UI tests must be simulator-signed: an unsigned build has no keychain entitlement, so guest
sign-in fails before any request screen. The simulator location is pinned to the demo zone.

Do not run a backend build while the Phase 1 `tools/run-phase1-local.sh` server is up: it
runs from `backend/build/classes`, and a rebuild under it produces 500s until it restarts.
