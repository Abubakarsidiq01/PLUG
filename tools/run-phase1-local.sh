#!/bin/sh
# Local-only disposable Phase 1 database; never use these defaults for staging.
set -eu
cd "$(dirname "$0")/.."
# This ignored, owner-managed file contains shell environment assignments.
if [ -f secrets/auth.env ]; then
    set -a
    . ./secrets/auth.env
    set +a
fi
cd backend
export PLUG_DATABASE_URL="${PLUG_DATABASE_URL:-jdbc:postgresql://127.0.0.1:55432/plug_validation}"
export PLUG_DATABASE_PASSWORD="${PLUG_DATABASE_PASSWORD:-local-validation-only}"
export PLUG_IDENTITY_PEPPER="${PLUG_IDENTITY_PEPPER:-local-validation-pepper-at-least-32-characters}"
# Real SMS must be selected explicitly; no silent file-delivery fallback.
export PLUG_IDENTITY_PHONE_DELIVERY="${PLUG_IDENTITY_PHONE_DELIVERY:-none}"
exec ./dev bootRun --args='--spring.profiles.active=db'
