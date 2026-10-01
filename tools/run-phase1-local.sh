#!/bin/sh
# Canonical local Phase 1 launcher. Preserve the configured database and identity pepper.
set -eu
cd "$(dirname "$0")/.."
for config in .env.local secrets/auth.env; do
    if [ -f "$config" ]; then
        set -a
        . "./$config"
        set +a
    fi
done
if [ "${PLUG_ENVIRONMENT:-local}" != local ]; then
    echo 'This launcher is local only; staging must use its staging profile and configuration.' >&2
    exit 1
fi
: "${PLUG_DATABASE_URL:?Set PLUG_DATABASE_URL in .env.local}"
: "${PLUG_DATABASE_PASSWORD:?Set PLUG_DATABASE_PASSWORD in .env.local}"
: "${PLUG_IDENTITY_PEPPER:?Set the existing PLUG_IDENTITY_PEPPER in .env.local}"
if [ "${#PLUG_IDENTITY_PEPPER}" -lt 32 ]; then
    echo 'PLUG_IDENTITY_PEPPER must contain at least 32 characters. Preserve existing identity keys.' >&2
    exit 1
fi
export PLUG_IDENTITY_PHONE_DELIVERY="${PLUG_IDENTITY_PHONE_DELIVERY:-none}"
case "$PLUG_IDENTITY_PHONE_DELIVERY" in
    none|development|twilio) ;;
    *) echo 'Phone delivery must be none, development or twilio.' >&2; exit 1 ;;
esac
if lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1; then
    echo 'Port 8080 is occupied. Stop the previous backend before restarting with new configuration.' >&2
    exit 1
fi
exec ./backend/dev bootRun --no-daemon --args='--spring.profiles.active=db --debug=false --trace=false'
