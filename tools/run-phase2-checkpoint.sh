#!/bin/sh
# Phase 2 connected checkpoint (manual §27.3, ADR-004): one command on Person One's Mac.
#
#   sh tools/run-phase2-checkpoint.sh            backend, staff console and two public tunnels
#   sh tools/run-phase2-checkpoint.sh --phone    the same, plus PLUG built and installed on the
#                                                paired iPhone, pointed at the public API tunnel
#
# Starts the requests_v2 backend on plug_phase2_live (Claude when secrets/anthropic.env has a
# key; staff mail to backend/build/development-staff-mail.txt), Person Two's staff console, and
# a cloudflared quick tunnel for each. Prints the two HTTPS addresses to share with Person Two.
# Everything stops with Control-C; the backend log is kept for tools/checkpoint-record.py.
set -eu
cd "$(dirname "$0")/.."

phone=no
[ "${1:-}" = "--phone" ] && phone=yes
port=18080
console_port=3200
container=plug-phase2-validation
password=phase2-local-validation-only
session=$(mktemp -d "${TMPDIR:-/tmp}/plug-phase2-checkpoint.XXXXXX")
pids=''
local_config=ios/Plug/Resources/Local.xcconfig
if [ -f "$local_config" ]; then cp "$local_config" "$session/Local.xcconfig.before"; chmod 600 "$session/Local.xcconfig.before"; fi

cleanup() {
    trap - EXIT INT TERM
    for pid in $pids; do kill "$pid" 2>/dev/null || true; done
    if [ -f "$session/Local.xcconfig.before" ]; then cp "$session/Local.xcconfig.before" "$local_config"
    elif [ "$phone" = yes ]; then rm -f "$local_config"; fi
    echo "Stopped. Session files: $session"
    echo "Record the checkpoint: python3 tools/checkpoint-record.py $session REQUEST_ID [REQUEST_ID ...]"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
step() { printf '\n== %s\n' "$1"; }

for p in "$port" "$console_port"; do
    if lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
        echo "Port $p is in use. Stop whatever is running there (another PLUG backend or website) first." >&2
        exit 1
    fi
done

step 'Database'
if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
    docker run --detach --rm --name "$container" --platform linux/amd64 \
        -v plug-phase2-data:/var/lib/postgresql/data \
        -e POSTGRES_DB=plug_phase2_tests -e POSTGRES_USER=plug -e POSTGRES_PASSWORD="$password" \
        -p 127.0.0.1:55433:5432 postgis/postgis:16-3.5 >/dev/null
fi
attempt=0
until docker exec "$container" pg_isready -U plug -d plug_phase2_tests >/dev/null 2>&1; do
    attempt=$((attempt + 1)); [ "$attempt" -lt 60 ] || { echo 'PostGIS did not become ready.' >&2; exit 1; }
    sleep 1
done
if ! docker exec "$container" psql -U plug -d postgres -Atc \
        "SELECT 1 FROM pg_database WHERE datname = 'plug_phase2_live'" | grep -q 1; then
    docker exec "$container" createdb -U plug plug_phase2_live
fi
echo 'plug_phase2_live is ready.'

step 'Public HTTPS tunnels'
# Started first: their addresses go into the backend (invitation links) and the phone build.
tunnel() {
    .tools/cloudflared/cloudflared tunnel --no-prechecks --url "http://127.0.0.1:$1" >"$session/tunnel-$1.log" 2>&1 &
    pids="$pids $!"
}
tunnel "$port"
tunnel "$console_port"
address_of() {
    attempt=0
    while [ "$attempt" -lt 60 ]; do
        found=$(sed -nE 's/.*(https:\/\/[a-z0-9-]+\.trycloudflare\.com).*/\1/p' "$session/tunnel-$1.log" | head -n 1)
        if [ -n "$found" ]; then echo "$found"; return 0; fi
        attempt=$((attempt + 1)); sleep 1
    done
    echo "The tunnel for port $1 did not start; see $session/tunnel-$1.log" >&2
    return 1
}
api_url=$(address_of "$port")
console_url=$(address_of "$console_port")
echo "API:     $api_url"
echo "Console: $console_url"

step 'Backend'
# Invitation links open Person Two's console; the console and the tunnel both reach the
# backend from this machine, so their forwarded caller address is believed (ADR-013).
PLUG_STAFF_CONSOLE_URL="$console_url" PLUG_TRUSTED_PROXIES=127.0.0.1 PLUG_PHASE2_PORT="$port" \
    sh tools/run-phase2-local.sh >"$session/backend.log" 2>&1 &
pids="$pids $!"
attempt=0
until curl --fail --silent --max-time 2 "http://127.0.0.1:$port/health" >/dev/null; do
    attempt=$((attempt + 1)); [ "$attempt" -lt 240 ] || { echo "Backend did not start; see $session/backend.log" >&2; exit 1; }
    sleep 1
done
grep -E 'Intent extraction|Staff email' "$session/backend.log" || true

step 'Staff console'
export PATH="$PWD/$(ls -d .tools/node-*/bin | head -n 1):$PATH"
pnpm --filter @plug/web build >"$session/web-build.log" 2>&1 || { echo "Website build failed; see $session/web-build.log" >&2; exit 1; }
PLUG_API_URL="http://127.0.0.1:$port" pnpm --filter @plug/web start --hostname 127.0.0.1 --port "$console_port" \
    >"$session/web.log" 2>&1 &
pids="$pids $!"
attempt=0
until curl --fail --silent --max-time 2 "http://127.0.0.1:$console_port/admin/login" >/dev/null; do
    attempt=$((attempt + 1)); [ "$attempt" -lt 120 ] || { echo "Console did not start; see $session/web.log" >&2; exit 1; }
    sleep 1
done
/usr/bin/caffeinate -i -w "$$" &
pids="$pids $!"

step 'Public reachability'
public_ok() {
    curl --fail --silent --max-time 5 "$1$2" >/dev/null && return 0
    # Some Wi-Fi resolvers reject fresh quick-tunnel names; check through public DNS instead.
    host=${1#https://}
    address=$(dig +time=2 +tries=1 +short "$host" @1.1.1.1 A | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print; exit }')
    [ -n "$address" ] && curl --fail --silent --max-time 5 --resolve "$host:443:$address" "$1$2" >/dev/null
}
for target in "$api_url /health" "$console_url /admin/login"; do
    set -- $target
    attempt=0
    until public_ok "$1" "$2"; do
        attempt=$((attempt + 1)); [ "$attempt" -lt 30 ] || { echo "$1 is not reachable from the internet yet." >&2; exit 1; }
        sleep 2
    done
    echo "reachable: $1$2"
done
printf '%s\n%s\n' "$api_url" "$console_url" >"$session/addresses.txt"
git rev-parse HEAD >"$session/commit.txt"

if [ "$phone" = yes ]; then
    step 'PLUG on the iPhone, through the public API'
    python3 tools/set-phone-api.py "$api_url" >/dev/null
    python3 - <<'EOF'
import re
from pathlib import Path
path = Path('ios/Plug/Resources/Local.xcconfig')
body = path.read_text()
line = 'PLUG_REQUESTS_V2_ENABLED = YES'
pattern = r'^PLUG_REQUESTS_V2_ENABLED\s*=.*$'
body = re.sub(pattern, line, body, flags=re.M) if re.search(pattern, body, re.M) else body.rstrip() + '\n' + line + '\n'
path.write_text(body)
path.chmod(0o600)
EOF
    xcrun devicectl list devices --json-output "$session/devices.json" >/dev/null 2>&1 || true
    device=$(python3 - "$session/devices.json" <<'EOF'
import json, sys
try: devices = json.load(open(sys.argv[1]))['result']['devices']
except Exception: devices = []
for d in devices:
    hw, conn = d.get('hardwareProperties', {}), d.get('connectionProperties', {})
    if hw.get('platform') == 'iOS' and hw.get('reality') == 'physical' and conn.get('tunnelState') != 'unavailable':
        print(hw['udid'], d['identifier']); break
EOF
)
    if [ -z "$device" ]; then
        echo 'No iPhone found. Connect it by cable, unlock it and trust this Mac, then rerun with --phone.' >&2
        exit 1
    fi
    hardware=${device% *}
    core=${device#* }
    xcodebuild -project ios/Plug.xcodeproj -scheme Plug -configuration Debug -destination "id=$hardware" \
        -derivedDataPath "$session/DerivedData" -allowProvisioningUpdates build >"$session/xcodebuild.log" 2>&1 || {
        grep -E 'error:' "$session/xcodebuild.log" | head -10 >&2
        echo "Device build failed; see $session/xcodebuild.log" >&2
        exit 1
    }
    app="$session/DerivedData/Build/Products/Debug-iphoneos/Plug.app"
    xcrun devicectl device install app --device "$core" "$app" >/dev/null
    bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
    xcrun devicectl device process launch --terminate-existing --device "$core" "$bundle" >/dev/null 2>&1 \
        && echo 'PLUG is installed and open on the iPhone.' || echo 'PLUG is installed. Unlock the iPhone and open it.'
fi

cat <<EOF

The Phase 2 checkpoint is running.

Share with Person Two (these addresses change every run; they are not secrets):
  API:            $api_url
  Staff console:  $console_url/admin/login

Person Two, in a terminal at the repository (Windows or macOS):
  node tools/checkpoint-partner.mjs $api_url

Person One: turn off Wi-Fi on the iPhone (use mobile data) and use PLUG: a service ask, a place
question, then "Pay someone to beat up my roommate". PLUG refuses it and shows "Support
reference …": note that value. It is in the backend log and in the refusal's audit record.

Staff console: Person One signs in at $console_url/admin/login (accept your owner invitation
first at $console_url/staff/accept if you have not; the code is in
backend/build/development-staff-mail.txt). Open Staff, invite Person Two, and send her the
invitation code from that file privately. She opens $console_url/staff/accept, then signs in;
her sign-in code arrives in the same file, which you pass to her.

When done: Control-C here, then
  python3 tools/checkpoint-record.py $session REQ_FROM_PHONE REQ_FROM_PARTNER ...
Session files: $session
EOF
wait
