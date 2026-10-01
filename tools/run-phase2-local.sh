#!/bin/sh
# Isolated Phase 2 app/QA server. Does not source the user's live .env.local.
# Create the disposable PostGIS databases using docs/runbooks/phase2-local.md.
set -eu
cd "$(dirname "$0")/.."

export PLUG_ENVIRONMENT=local
export PLUG_BIND_ADDRESS=127.0.0.1
export PLUG_DATABASE_URL="${PLUG_DATABASE_URL:-jdbc:postgresql://127.0.0.1:55433/plug_phase2_live}"
export PLUG_DATABASE_USER="${PLUG_DATABASE_USER:-plug}"
export PLUG_DATABASE_PASSWORD="${PLUG_DATABASE_PASSWORD:-phase2-local-validation-only}"
export PLUG_IDENTITY_PEPPER="${PLUG_IDENTITY_PEPPER:-phase2-local-test-pepper-not-for-real-use}"
export PLUG_REQUESTS_V2_ENABLED=true
export PLUG_IDENTITY_PHONE_DELIVERY=none

case "$PLUG_DATABASE_URL" in
    jdbc:postgresql://127.0.0.1:*/plug_phase2_live) ;;
    *) echo 'This launcher requires a loopback plug_phase2_live database, separate from automated test resets.' >&2; exit 1 ;;
esac
plug_phase2_port="${PLUG_PHASE2_PORT:-18080}"
case "$plug_phase2_port" in
    ''|*[!0-9]*) echo 'PLUG_PHASE2_PORT must be a numeric TCP port.' >&2; exit 1 ;;
esac
if [ "$plug_phase2_port" -lt 1024 ] || [ "$plug_phase2_port" -gt 65535 ]; then
    echo 'PLUG_PHASE2_PORT must be between 1024 and 65535.' >&2
    exit 1
fi
if lsof -nP -iTCP:"$plug_phase2_port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $plug_phase2_port is occupied; this launcher will not stop the existing process." >&2
    exit 1
fi
# Never run a JAR directly from build/libs: another build replaces it while
# Spring is still lazily loading classes, causing runtime NoClassDefFoundError.
./backend/dev bootJar --no-daemon
plug_phase2_jar=backend/build/libs/plug-api-0.0.1-SNAPSHOT.jar
plug_phase2_runtime=$(mktemp -d "${TMPDIR:-/tmp}/plug-phase2-runtime.XXXXXX")
cp "$plug_phase2_jar" "$plug_phase2_runtime/plug-api.jar"
if ! cmp -s "$plug_phase2_jar" "$plug_phase2_runtime/plug-api.jar"; then
    echo 'The build changed during snapshot creation. Retry after the other build finishes.' >&2
    exit 1
fi
plug_phase2_java=''
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    plug_phase2_java="$JAVA_HOME/bin/java"
else
    for plug_phase2_jdk in .tools/jdk-*/Contents/Home; do
        if [ -x "$plug_phase2_jdk/bin/java" ]; then
            plug_phase2_java="$plug_phase2_jdk/bin/java"
            break
        fi
    done
fi
if [ -z "$plug_phase2_java" ]; then plug_phase2_java=$(command -v java); fi
echo "Phase 2 uses an immutable runtime snapshot at $plug_phase2_runtime"
exec "$plug_phase2_java" -jar "$plug_phase2_runtime/plug-api.jar" \
    --spring.profiles.active=db --server.port="$plug_phase2_port" --debug=false --trace=false
