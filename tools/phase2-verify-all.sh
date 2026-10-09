#!/bin/sh
# Every automated Phase 2 check against disposable data only:
#   backend unit + database tests, contract/fixture checks, web typecheck/lint, OpenAPI lint,
#   the live API suite and Bruno (each on its own fresh backend), iOS unit tests with live
#   sign-in, and the simulator state screenshots.
# Independent work runs side by side: the web checks run beside the backend tests, and the
# simulator walkthroughs beside the API suites. The disposable backends use a ten-second rate window
# (PLUG_RATE_WINDOW_SECONDS, local only), so the limits are proved with the same counts
# without sitting out real minutes.
#   PLUG_VERIFY_SKIP_UI=1   skip the simulator screenshots (for a quick pre-push run)
# Never touches the Phase 1 database, the phone backend or provider credentials.
set -eu
cd "$(dirname "$0")/.."

node_bin=$(ls -d .tools/node-*/bin 2>/dev/null | head -n 1)
[ -n "$node_bin" ] && PATH="$PWD/$node_bin:$PATH"
command -v node >/dev/null || { echo 'Node 22 is required (bundled under .tools or on PATH).' >&2; exit 1; }
container=plug-phase2-validation
password=phase2-local-validation-only
pepper=phase2-local-test-pepper-not-for-real-use
live_port="${PLUG_VERIFY_PORT:-18083}"
bruno_port=$((live_port + 2))
window=10
work=$(mktemp -d "${TMPDIR:-/tmp}/plug-phase2-verify.XXXXXX")
simulator="${PLUG_SIMULATOR:-iPhone 17 Pro}"
skip_ui="${PLUG_VERIFY_SKIP_UI:-}"
pids=''
cleanup() { for pid in $pids; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM
# A Mac that idles to sleep pauses every step, and a paused audit or request times out.
# This holds off idle sleep until the script ends; closing the lid on battery still sleeps.
command -v caffeinate >/dev/null && { caffeinate -i -w $$ & }
started=$(date +%s)
step() { printf '\n== %s (%ss)\n' "$1" "$(($(date +%s) - started))"; }
# Runs a command in the background with its output in $work/<name>.log; "finish <name>"
# waits for it and prints the log's tail if it failed.
background() { name=$1; shift; "$@" >"$work/$name.log" 2>&1 & eval "pid_$name=$!"; pids="$pids $!"; }
finish() {
    eval "pid=\$pid_$1"
    wait "$pid" || { tail -n "${2:-30}" "$work/$1.log" >&2; echo "See $work/$1.log" >&2; exit 1; }
}

step 'Disposable PostGIS'
if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
    docker run --detach --rm --name "$container" --platform linux/amd64 \
        -v plug-phase2-data:/var/lib/postgresql/data \
        -e POSTGRES_DB=plug_phase2_tests -e POSTGRES_USER=plug -e POSTGRES_PASSWORD="$password" \
        -p 127.0.0.1:55433:5432 postgis/postgis:16-3.5 >/dev/null
fi
until docker exec "$container" pg_isready -U plug -d plug_phase2_tests >/dev/null 2>&1; do sleep 1; done
# Every database is disposable: rows left by one run must never decide the next.
for db in plug_phase2_tests plug_phase2_verify plug_phase2_bruno; do
    docker exec "$container" dropdb -U plug --if-exists --force "$db"
    docker exec "$container" createdb -U plug "$db"
done

web_checks() {
    pnpm install --frozen-lockfile
    pnpm test:contracts
    pnpm --filter @plug/web typecheck
    pnpm --filter @plug/web lint
    npx --yes @stoplight/spectral-cli@6.15.0 lint contracts/openapi.yaml --fail-severity warn
}
background web web_checks

step 'Backend: unit, database, Checkstyle, boot JAR'
PLUG_DATABASE_URL=jdbc:postgresql://127.0.0.1:55433/plug_phase2_tests PLUG_DATABASE_USER=plug \
    PLUG_DATABASE_PASSWORD="$password" PLUG_IDENTITY_PEPPER="$pepper" \
    ./backend/dev check databaseTest bootJar --rerun-tasks >"$work/backend.log" 2>&1 \
    || { grep -E 'FAILED|error:' "$work/backend.log" | head -20 >&2; echo "See $work/backend.log" >&2; exit 1; }
echo 'passed'

# The walkthroughs start now rather than beside Gradle: they then share the machine only with
# the API suites, which mostly wait, and the backend tests keep their timings.
if [ -z "$skip_ui" ]; then
    background ui env PLUG_SIMULATOR="$simulator" sh tools/run-phase2-ui-evidence.sh
fi

step "Fresh isolated backends on 127.0.0.1:$live_port (live suite) and :$bruno_port (Bruno, iOS)"
jar="$work/plug-api.jar"
cp backend/build/libs/plug-api-0.0.1-SNAPSHOT.jar "$jar"
java=$(ls -d .tools/jdk-*/Contents/Home/bin/java 2>/dev/null | head -n 1)
[ -n "$java" ] || java=$(command -v java)
# No ANTHROPIC_API_KEY: the labelled dataset asserts the deterministic rules, reproducibly.
serve() {
    ANTHROPIC_API_KEY= PLUG_ENVIRONMENT=local PLUG_BIND_ADDRESS=127.0.0.1 PLUG_REQUESTS_V2_ENABLED=true \
        PLUG_IDENTITY_PHONE_DELIVERY=none PLUG_STAFF_MAIL_DELIVERY=none PLUG_RATE_WINDOW_SECONDS=$window \
        PLUG_DATABASE_URL="jdbc:postgresql://127.0.0.1:55433/$2" PLUG_DATABASE_USER=plug \
        PLUG_DATABASE_PASSWORD="$password" PLUG_IDENTITY_PEPPER="$pepper" \
        exec "$java" -jar "$jar" --spring.profiles.active=db --server.port="$1"
}
background api_live serve "$live_port" plug_phase2_verify
background api_bruno serve "$bruno_port" plug_phase2_bruno
for port in "$live_port" "$bruno_port"; do
    attempt=0
    until curl --fail --silent --max-time 2 "http://127.0.0.1:$port/health" >/dev/null; do
        attempt=$((attempt + 1)); [ "$attempt" -lt 180 ] || { echo "Backend on $port did not start; see $work." >&2; exit 1; }
        sleep 1
    done
done
echo 'healthy'

step 'Live API acceptance suite and Bruno, side by side'
mkdir -p evidence/P2/security
report="${PHASE2_REPORT:-evidence/P2/security/phase2-live-$(date +%Y-%m-%d).json}"
background live env PHASE2_DISPOSABLE=1 PHASE2_BASE_URL="http://127.0.0.1:$live_port" PHASE2_REPORT="$report" \
    PHASE2_RATE_WINDOW_SECONDS=$window node tools/phase2-live.mjs
(cd tests/phase2 && ../../tools/bruno/node_modules/.bin/bru run --env local \
    --env-var baseUrl="http://127.0.0.1:$bruno_port" >"$work/bruno.log" 2>&1) \
    || { tail -30 "$work/bruno.log" >&2; exit 1; }
grep -E '│ (Status|Requests|Tests|Assertions) ' "$work/bruno.log" | tr -s ' '
finish live 3
tail -n 1 "$work/live.log"
echo "Report: $report"

step 'Contracts, fixtures, labelled dataset, web typecheck and lint, Spectral'
finish web
grep -E '^# (pass|fail)' "$work/web.log"

if [ -z "$skip_ui" ]; then
    step 'iOS simulator state screenshots'
    finish ui 8
    tail -n 1 "$work/ui.log"
fi

# The simulator is free once the screenshots are done; Bruno's backend is idle by now.
step 'iOS unit tests, live sign-in against a fresh backend'
sim=$(xcrun simctl list devices available | sed -nE "s/^ +$simulator \(([0-9A-F-]+)\).*/\1/p" | head -n 1)
[ -n "$sim" ] || { echo "No simulator named '$simulator'." >&2; exit 1; }
TEST_RUNNER_PLUG_INTEGRATION_API_URL="http://127.0.0.1:$bruno_port" xcodebuild test \
    -project ios/Plug.xcodeproj -scheme Plug -destination "id=$sim" >"$work/ios-unit.log" 2>&1 \
    || { grep -E 'error:|Executed' "$work/ios-unit.log" | tail -8 >&2; exit 1; }
grep -E 'Executed [0-9]+ tests' "$work/ios-unit.log" | tail -n 1

cat <<EOF

All automated Phase 2 checks passed in $(($(date +%s) - started))s. Logs: $work
${skip_ui:+Simulator screenshots were skipped (PLUG_VERIFY_SKIP_UI).
}Not provable here: physical-device screenshots (tools/run-phase2-device-evidence.sh),
Figma review, the Windows run and the two-person checkpoint.
EOF
