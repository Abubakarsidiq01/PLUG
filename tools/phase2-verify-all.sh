#!/bin/sh
# Every automated Phase 2 check, in order, against disposable data only:
#   backend unit + database tests, contract/fixture checks, web typecheck/lint, OpenAPI lint,
#   a fresh isolated backend for the live API suite, Bruno and the iOS live sign-in test,
#   iOS unit tests, then simulator state screenshots.
# Never touches the Phase 1 database, the phone backend or provider credentials.
# What it cannot prove (physical device, Figma, Windows, two-person G2) is listed at the end.
set -eu
cd "$(dirname "$0")/.."

node_bin=$(ls -d .tools/node-*/bin 2>/dev/null | head -n 1)
[ -n "$node_bin" ] && PATH="$PWD/$node_bin:$PATH"
command -v node >/dev/null || { echo 'Node 22 is required (bundled under .tools or on PATH).' >&2; exit 1; }
container=plug-phase2-validation
password=phase2-local-validation-only
pepper=phase2-local-test-pepper-not-for-real-use
live_port="${PLUG_VERIFY_PORT:-18083}"
live_db=plug_phase2_verify
work=$(mktemp -d "${TMPDIR:-/tmp}/plug-phase2-verify.XXXXXX")
simulator="${PLUG_SIMULATOR:-iPhone 17 Pro}"
backend_pid=''
cleanup() { if [ -n "$backend_pid" ]; then kill "$backend_pid" 2>/dev/null || true; fi; }
trap cleanup EXIT INT TERM
step() { printf '\n== %s\n' "$1"; }

step 'Disposable PostGIS'
if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
    docker run --detach --rm --name "$container" --platform linux/amd64 \
        -e POSTGRES_DB=plug_phase2_tests -e POSTGRES_USER=plug -e POSTGRES_PASSWORD="$password" \
        -p 127.0.0.1:55433:5432 postgis/postgis:16-3.5 >/dev/null
fi
until docker exec "$container" pg_isready -U plug -d plug_phase2_tests >/dev/null 2>&1; do sleep 1; done
docker exec "$container" dropdb -U plug --if-exists "$live_db"
docker exec "$container" createdb -U plug "$live_db"

step 'Backend: unit, database, Checkstyle, boot JAR'
PLUG_DATABASE_URL=jdbc:postgresql://127.0.0.1:55433/plug_phase2_tests PLUG_DATABASE_USER=plug \
    PLUG_DATABASE_PASSWORD="$password" PLUG_IDENTITY_PEPPER="$pepper" \
    ./backend/dev check databaseTest bootJar --rerun-tasks >"$work/backend.log" 2>&1 \
    || { grep -E 'FAILED|error:' "$work/backend.log" | head -20 >&2; echo "See $work/backend.log" >&2; exit 1; }
echo 'passed'

step 'Contracts, fixtures and labelled dataset'
pnpm install --frozen-lockfile >/dev/null
pnpm test:contracts 2>&1 | grep -E '^# (pass|fail)'

step 'Web typecheck and lint'
pnpm --filter @plug/web typecheck >/dev/null
pnpm --filter @plug/web lint >/dev/null
echo 'passed'

step 'OpenAPI lint (Spectral, CI settings)'
npx --yes @stoplight/spectral-cli@6.15.0 lint contracts/openapi.yaml --fail-severity warn

step "Fresh isolated backend on 127.0.0.1:$live_port"
jar="$work/plug-api.jar"
cp backend/build/libs/plug-api-0.0.1-SNAPSHOT.jar "$jar"
java=$(ls -d .tools/jdk-*/Contents/Home/bin/java 2>/dev/null | head -n 1)
[ -n "$java" ] || java=$(command -v java)
# No ANTHROPIC_API_KEY: the labelled dataset asserts the deterministic rules, reproducibly.
ANTHROPIC_API_KEY= PLUG_ENVIRONMENT=local PLUG_BIND_ADDRESS=127.0.0.1 PLUG_REQUESTS_V2_ENABLED=true PLUG_IDENTITY_PHONE_DELIVERY=none \
    PLUG_DATABASE_URL="jdbc:postgresql://127.0.0.1:55433/$live_db" PLUG_DATABASE_USER=plug \
    PLUG_DATABASE_PASSWORD="$password" PLUG_IDENTITY_PEPPER="$pepper" \
    "$java" -jar "$jar" --spring.profiles.active=db --server.port="$live_port" >"$work/live-backend.log" 2>&1 &
backend_pid=$!
attempt=0
until curl --fail --silent --max-time 2 "http://127.0.0.1:$live_port/health" >/dev/null; do
    kill -0 "$backend_pid" 2>/dev/null || { tail -20 "$work/live-backend.log" >&2; exit 1; }
    attempt=$((attempt + 1)); [ "$attempt" -lt 180 ] || { echo 'Live backend did not start.' >&2; exit 1; }
    sleep 1
done
echo 'healthy'

step 'Live API acceptance suite (observes real rate windows; several minutes)'
mkdir -p evidence/P2/security
report="evidence/P2/security/phase2-live-$(date +%Y-%m-%d).json"
# Exit status of the suite itself, not of a pipe: a failed check must stop the run.
PHASE2_DISPOSABLE=1 PHASE2_BASE_URL="http://127.0.0.1:$live_port" PHASE2_REPORT="$report" \
    node tools/phase2-live.mjs >"$work/live.log" 2>&1 || { tail -n 3 "$work/live.log" >&2; exit 1; }
tail -n 1 "$work/live.log"
echo "Report: $report"

step 'Phase 2 Bruno collection'
sleep 65   # let the suite's rate-limit windows expire (docs/testing/phase2-qa-runbook.md)
(cd tests/phase2 && ../../tools/bruno/node_modules/.bin/bru run --env local \
    --env-var baseUrl="http://127.0.0.1:$live_port" >"$work/bruno.log" 2>&1) \
    || { tail -30 "$work/bruno.log" >&2; exit 1; }
grep -E '│ (Status|Requests|Tests|Assertions) ' "$work/bruno.log" | tr -s ' '

step 'iOS unit tests, live sign-in against the fresh backend'
sim=$(xcrun simctl list devices available | sed -nE "s/^ +$simulator \(([0-9A-F-]+)\).*/\1/p" | head -n 1)
[ -n "$sim" ] || { echo "No simulator named '$simulator'." >&2; exit 1; }
TEST_RUNNER_PLUG_INTEGRATION_API_URL="http://127.0.0.1:$live_port" xcodebuild test \
    -project ios/Plug.xcodeproj -scheme Plug -destination "id=$sim" >"$work/ios-unit.log" 2>&1 \
    || { grep -E 'error:|Executed' "$work/ios-unit.log" | tail -8 >&2; exit 1; }
grep -E 'Executed [0-9]+ tests' "$work/ios-unit.log" | tail -n 1
kill "$backend_pid" 2>/dev/null || true
backend_pid=''

step 'iOS simulator state screenshots'
PLUG_SIMULATOR="$simulator" sh tools/run-phase2-ui-evidence.sh

cat <<EOF

All automated Phase 2 checks passed. Logs: $work
Not provable here, and still required for G2:
  - Physical-device screenshots and VoiceOver walkthrough (tools/run-phase2-phone.sh, then capture)
  - Figma review, Person Two's Windows run, contract 0.3.0 approval by both engineers
  - The two-person connected checkpoint and both G2 signatures
EOF
