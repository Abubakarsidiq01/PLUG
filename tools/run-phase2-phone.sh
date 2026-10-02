#!/bin/sh
# One command for the Phase 2 phone flow: disposable PostGIS, the isolated requests_v2
# backend, an HTTPS development tunnel (ADR-004), and a signed Debug build installed and
# launched on the paired iPhone. Stop with Control-C; the backend, tunnel and sleep
# prevention stop with it. No provider secrets are loaded (see docs/runbooks/phase2-local.md).
set -eu
cd "$(dirname "$0")/.."

port="${PLUG_PHASE2_PORT:-18080}"
container=plug-phase2-validation
password=phase2-local-validation-only
run_dir=$(mktemp -d "${TMPDIR:-/tmp}/plug-phase2-phone.XXXXXX")
backend_pid=''
tunnel_pid=''
awake_pid=''

cleanup() {
    trap - EXIT INT TERM
    for pid in "$tunnel_pid" "$backend_pid" "$awake_pid"; do
        if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
    done
    # Later Xcode builds against the flag-off Phase 1 backend must not show the Ask flow.
    set_local PLUG_REQUESTS_V2_ENABLED NO
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

set_local() {
    python3 - "$1" "$2" <<'EOF'
import re, sys
from pathlib import Path
key, value = sys.argv[1], sys.argv[2]
path = Path('ios/Plug/Resources/Local.xcconfig')
body = path.read_text() if path.exists() else ''
line = f'{key} = {value}'
pattern = rf'^{key}\s*=.*$'
body = re.sub(pattern, line, body, flags=re.M) if re.search(pattern, body, re.M) else body.rstrip() + '\n' + line + '\n'
path.write_text(body)
path.chmod(0o600)
EOF
}

step() { printf '\n== %s\n' "$1"; }

step 'Disposable database'
if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
    docker run --detach --rm --name "$container" --platform linux/amd64 \
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

step "Phase 2 backend on 127.0.0.1:$port"
PLUG_PHASE2_PORT="$port" sh tools/run-phase2-local.sh >"$run_dir/backend.log" 2>&1 &
backend_pid=$!
attempt=0
until curl --fail --silent --max-time 2 "http://127.0.0.1:$port/health" >/dev/null; do
    kill -0 "$backend_pid" 2>/dev/null || { echo "Backend stopped; see $run_dir/backend.log" >&2; tail -20 "$run_dir/backend.log" >&2; exit 1; }
    attempt=$((attempt + 1)); [ "$attempt" -lt 180 ] || { echo 'Backend did not become healthy.' >&2; exit 1; }
    sleep 1
done
# With requests_v2 on, an anonymous create is refused (401); the flag-off stub would accept it.
status=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 5 -X POST \
    -H 'Content-Type: application/json' -d '{}' "http://127.0.0.1:$port/v1/requests")
[ "$status" = 401 ] || { echo "requests_v2 is not active on port $port (anonymous create returned $status)." >&2; exit 1; }
echo 'Healthy, requests_v2 active.'

step 'HTTPS tunnel'
.tools/cloudflared/cloudflared tunnel --no-prechecks --url "http://127.0.0.1:$port" >"$run_dir/tunnel.log" 2>&1 &
tunnel_pid=$!
/usr/bin/caffeinate -i -w "$tunnel_pid" &
awake_pid=$!
url=''
attempt=0
while [ "$attempt" -lt 45 ]; do
    kill -0 "$tunnel_pid" 2>/dev/null || { echo "Tunnel stopped; see $run_dir/tunnel.log" >&2; exit 1; }
    candidate=$(sed -nE 's/.*(https:\/\/[a-z0-9-]+\.trycloudflare\.com).*/\1/p' "$run_dir/tunnel.log" | head -n 1)
    if [ -n "$candidate" ]; then
        host=${candidate#https://}
        address=$(dig +time=2 +tries=1 +short "$host" @1.1.1.1 A | awk '/^[0-9.]+$/ { print; exit }')
        # Fresh quick-tunnel names are often missing from Wi-Fi resolvers for a while, so
        # health is checked through public DNS; the phone may need mobile data briefly.
        if [ -n "$address" ] && curl --fail --silent --max-time 4 --resolve "$host:443:$address" "$candidate/health" >/dev/null; then
            url=$candidate
            break
        fi
    fi
    attempt=$((attempt + 1))
    sleep 2
done
[ -n "$url" ] || { echo "Tunnel did not become healthy; see $run_dir/tunnel.log" >&2; exit 1; }
python3 tools/set-phone-api.py "$url"
set_local PLUG_REQUESTS_V2_ENABLED YES
echo "Phone API: $url"

step 'Signed build for the paired iPhone'
find_iphone() {
    xcrun devicectl list devices --json-output "$run_dir/devices.json" >/dev/null 2>&1 || return 0
    python3 - "$run_dir/devices.json" <<'EOF'
import json, sys
devices = json.load(open(sys.argv[1]))['result']['devices']
for d in devices:
    hw, conn = d.get('hardwareProperties', {}), d.get('connectionProperties', {})
    if hw.get('platform') == 'iOS' and hw.get('reality') == 'physical' and conn.get('tunnelState') != 'unavailable':
        print(hw['udid'], d['identifier']); break
EOF
}
udid=$(find_iphone)
if [ -z "$udid" ]; then
    echo 'Waiting for the iPhone: connect it by cable (or the same Wi-Fi), unlock it and trust this Mac.'
    until [ -n "$udid" ]; do
        kill -0 "$tunnel_pid" 2>/dev/null || { echo 'Tunnel stopped while waiting.' >&2; exit 1; }
        sleep 5
        udid=$(find_iphone)
    done
fi
hardware=${udid% *}
core=${udid#* }
xcodebuild -project ios/Plug.xcodeproj -scheme Plug -configuration Debug \
    -destination "id=$hardware" -derivedDataPath "$run_dir/DerivedData" \
    -allowProvisioningUpdates build >"$run_dir/xcodebuild.log" 2>&1 || {
    grep -E 'error:' "$run_dir/xcodebuild.log" | head -20 >&2
    echo "Device build failed; see $run_dir/xcodebuild.log" >&2
    exit 1
}
app="$run_dir/DerivedData/Build/Products/Debug-iphoneos/Plug.app"
xcrun devicectl device install app --device "$core" "$app" >/dev/null
bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
# A locked phone refuses the launch; the install already succeeded, so keep everything running.
if xcrun devicectl device process launch --terminate-existing --device "$core" "$bundle" >/dev/null 2>&1; then
    echo 'Installed and launched PLUG on the iPhone.'
else
    echo 'Installed PLUG on the iPhone. It was locked, so unlock it and open PLUG yourself.'
fi

cat <<EOF

PLUG Phase 2 is running on your iPhone.
  1. Continue as guest (Google needs provider configuration this isolated backend omits).
  2. Ask: "I need to repair my shoe for \$45 tomorrow". Any lawful service works (ADR-009).
     With no participating supplier, the request ends No matches and the app lists nearby
     businesses from Apple Maps with price and availability Unknown.
  3. Seeded offers exist only for barber and beauty in the synthetic Ruston, LA zone. Type a
     Ruston address such as "Railroad Ave, Ruston, LA" to see them. Try "Need a cut and my
     nails done" for the one question, and cancel while it is searching.
  Extraction uses Claude when ANTHROPIC_API_KEY is in secrets/anthropic.env, else the rules.
If the phone cannot reach $url on Wi-Fi, switch to mobile data for a minute.
Logs: $run_dir. Keep this terminal and the lid open; Control-C stops everything.
EOF
wait "$tunnel_pid"
