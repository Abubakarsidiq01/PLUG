#!/bin/sh
# Starts the backend the way Phase 1 needs it, and refuses to start it any other way.
#
# `./gradlew bootRun` on its own looks like it works and is not what you want: with no
# profile the identity module is switched off, so every /v1/auth route answers 403 and the
# reason is nowhere on screen. This script makes that mistake impossible.
#
#   sh tools/run-backend-local.sh
#
# It reads .env.local if there is one, so the secrets are not in your shell history.
set -eu

cd "$(dirname "$0")/.."
root=$(pwd)

if [ -f .env.local ]; then
    set -a
    . ./.env.local
    set +a
    echo "config      : .env.local"
else
    echo "config      : .env.local not found — using the environment as it stands"
fi

missing=""
[ -n "${PLUG_DATABASE_PASSWORD:-}" ] || missing="$missing PLUG_DATABASE_PASSWORD"
[ -n "${PLUG_IDENTITY_PEPPER:-}" ] || missing="$missing PLUG_IDENTITY_PEPPER"
if [ -n "$missing" ]; then
    echo "" >&2
    echo "Missing required configuration:$missing" >&2
    echo "" >&2
    echo "Copy .env.example to .env.local and fill them in. The pepper must be at least" >&2
    echo "32 characters; it keys the one-way values stored for phone numbers, Apple" >&2
    echo "subjects and one-time codes, so treat it as permanent once anything is stored." >&2
    exit 1
fi

if [ "${#PLUG_IDENTITY_PEPPER}" -lt 32 ]; then
    echo "PLUG_IDENTITY_PEPPER is ${#PLUG_IDENTITY_PEPPER} characters; it must be at least 32." >&2
    exit 1
fi

# A database has to be answering, or Flyway fails in a way that reads like a code problem.
if ! nc -z 127.0.0.1 5432 >/dev/null 2>&1; then
    echo "" >&2
    echo "Nothing is listening on 127.0.0.1:5432." >&2
    echo "Start it first:  docker compose --env-file .env.local up -d --wait postgres" >&2
    exit 1
fi
echo "database    : reachable on 127.0.0.1:5432"

# If a backend is already up, say what it is rather than failing on the port binding.
if lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1; then
    echo ""
    echo "Port 8080 is already in use. Checking what is there:"
    health=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8080/health || echo "000")
    guest=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X POST \
        http://127.0.0.1:8080/v1/auth/guest -H 'Content-Type: application/json' \
        -d '{"consent_version":"2026-09-01"}' || echo "000")
    echo "  GET  /health          -> $health"
    echo "  POST /v1/auth/guest   -> $guest"
    echo ""
    if [ "$guest" = "201" ]; then
        echo "That is already a Phase 1 backend with the identity module enabled."
        echo "Nothing to do — use the one that is running."
        exit 0
    fi
    echo "That is NOT a Phase 1 backend: the identity module is off or it is an older build."
    echo "Stop it and run this script again:"
    echo "  lsof -nP -iTCP:8080 -sTCP:LISTEN     # find the pid"
    echo "  kill <pid>"
    exit 1
fi

echo "port        : 8080 free"
echo "starting    : profile=db, phone delivery=development (local only, writes to build/)"
echo ""
exec ./backend/dev bootRun --no-daemon \
    --args='--spring.profiles.active=db --plug.identity.phone-delivery=development'
