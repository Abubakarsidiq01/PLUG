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
# ADR-009: Claude extraction needs only ANTHROPIC_API_KEY. Read that one line, never the
# whole file, so no other provider secret reaches this isolated runtime. Unset: rules only.
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    for plug_key_file in secrets/anthropic.env .env.local; do
        [ -f "$plug_key_file" ] || continue
        plug_key=$(sed -n 's/^ANTHROPIC_API_KEY=//p' "$plug_key_file" | tail -n 1 | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//')
        if [ -n "$plug_key" ]; then export ANTHROPIC_API_KEY="$plug_key"; break; fi
    done
fi
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then echo 'Intent extraction: Claude (rules on any failure).'
else echo 'Intent extraction: built-in rules (set ANTHROPIC_API_KEY in secrets/anthropic.env for Claude).'; fi

# ADR-013 staff accounts. secrets/staff.env may set PLUG_STAFF_OWNER_EMAIL (the first owner,
# invited once while no staff account exists) and, for real email, RESEND_API_KEY and
# PLUG_STAFF_MAIL_FROM. Only those three lines are read. Without a Resend key, staff mail goes
# to the owner-only file backend/build/development-staff-mail.txt on this machine.
for plug_staff_var in PLUG_STAFF_OWNER_EMAIL RESEND_API_KEY PLUG_STAFF_MAIL_FROM; do
    eval "plug_staff_current=\${$plug_staff_var:-}"
    if [ -z "$plug_staff_current" ] && [ -f secrets/staff.env ]; then
        plug_staff_value=$(sed -n "s/^$plug_staff_var=//p" secrets/staff.env | tail -n 1 | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//')
        if [ -n "$plug_staff_value" ]; then export "$plug_staff_var=$plug_staff_value"; fi
    fi
done
if [ -n "${RESEND_API_KEY:-}" ]; then
    export PLUG_STAFF_MAIL_DELIVERY=resend
    echo 'Staff email: Resend.'
else
    export PLUG_STAFF_MAIL_DELIVERY=development
    export PLUG_STAFF_DEVELOPMENT_MAIL_FILE="$PWD/backend/build/development-staff-mail.txt"
    echo "Staff email: local file $PLUG_STAFF_DEVELOPMENT_MAIL_FILE (set RESEND_API_KEY in secrets/staff.env for real email)."
fi

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
