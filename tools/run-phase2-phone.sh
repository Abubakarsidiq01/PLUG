#!/bin/sh
# One command for the Phase 2 phone flow: disposable PostGIS, the isolated requests_v2
# backend, a private paired-device relay, and a signed Debug build installed and
# launched on the paired iPhone. Stop with Control-C; the backend, relay and sleep
# prevention stop with it. No provider secrets are loaded (see docs/runbooks/phase2-local.md).
set -eu
cd "$(dirname "$0")/.."

port="${PLUG_PHASE2_PORT:-18080}"
container=plug-phase2-validation
password=phase2-local-validation-only
run_dir=$(mktemp -d "${TMPDIR:-/tmp}/plug-phase2-phone.XXXXXX")
backend_pid=''
relay_pid=''
awake_pid=''
paired_pid=''
local_config=ios/Plug/Resources/Local.xcconfig
if [ -f "$local_config" ]; then
    cp "$local_config" "$run_dir/Local.xcconfig.before"
    chmod 600 "$run_dir/Local.xcconfig.before"
fi

cleanup() {
    trap - EXIT INT TERM
    for pid in "$relay_pid" "$backend_pid" "$awake_pid" "$paired_pid"; do
        if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
    done
    # Restore the developer's prior build settings, including on early failures.
    if [ -f "$run_dir/Local.xcconfig.before" ]; then
        cp "$run_dir/Local.xcconfig.before" "$local_config"
    else
        rm -f "$local_config"
    fi
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
        kill -0 "$backend_pid" 2>/dev/null || { echo 'Backend stopped while waiting.' >&2; exit 1; }
        sleep 5
        udid=$(find_iphone)
    done
fi
hardware=${udid% *}
core=${udid#* }
step 'Private paired connection'
xcrun devicectl device notification observe --device "$core" \
    --name app.plug.development.keepalive --session-timeout 14400 --timeout 14430 \
    >"$run_dir/paired.log" 2>&1 &
paired_pid=$!
xcrun devicectl device info details --device "$core" --json-output "$run_dir/details.json" >/dev/null
addresses=$(python3 - "$run_dir/details.json" <<'EOF'
import ipaddress, json, re, subprocess, sys
peer = ipaddress.ip_address(json.load(open(sys.argv[1]))['result']['connectionProperties']['tunnelIPAddress'])
network = ipaddress.ip_network(str(peer) + '/64', strict=False)
for candidate in re.findall(r'inet6 ([0-9a-f:]+)', subprocess.check_output(['ifconfig'], text=True)):
    host = ipaddress.ip_address(candidate)
    if host != peer and host in network and host in ipaddress.ip_network('fd00::/8'):
        print(host, peer)
        break
EOF
)
[ -n "$addresses" ] || { echo 'No paired interface. Reconnect and unlock the iPhone.' >&2; exit 1; }
paired_host=${addresses% *}
paired_peer=${addresses#* }
python3 tools/paired-phone-relay.py --host "$paired_host" --peer "$paired_peer" \
    --upstream-port "$port" >"$run_dir/relay.log" 2>&1 &
relay_pid=$!
attempt=0
until lsof -nP -a -p "$relay_pid" -iTCP:18086 -sTCP:LISTEN >/dev/null; do
    kill -0 "$relay_pid" 2>/dev/null || { cat "$run_dir/relay.log" >&2; exit 1; }
    attempt=$((attempt + 1)); [ "$attempt" -lt 20 ] || { echo 'Paired relay did not bind.' >&2; exit 1; }
    sleep 1
done
/usr/bin/caffeinate -i -w "$relay_pid" &
awake_pid=$!
url="http://[$paired_host]:18086"
# xcconfig treats // as a comment. The empty expansion preserves the URL in the build.
set_local PLUG_DEVELOPMENT_API_URL "http:/\$()/[$paired_host]:18086"
set_local PLUG_REQUESTS_V2_ENABLED YES
echo "Phone API: $url"

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
  2. Ask a service: "I need to repair my shoe for \$45 tomorrow". Skills come from
     contracts/skills.yaml (manual v4). With no provider nearby it ends No offers, honestly.
  3. Ask a place: "How long is the line at Walmart right now?" shows real counts, then Unknown.
  4. Seeded offers exist for barber and beauty in the synthetic Ruston, LA zone. Type a Ruston
     address such as "Railroad Ave, Ruston, LA". "Something" gets the one question; tap
     Stop asking while it searches.
  5. Offer a service: describe what you do, keep the chips, save; the Inbox tab appears.
  Extraction uses Claude when ANTHROPIC_API_KEY is in secrets/anthropic.env, else the rules.
Keep the phone paired with this Mac. If reconnected, rerun this launcher to refresh its private address.
Logs: $run_dir. Keep this terminal and the lid open; Control-C stops everything.
EOF
wait "$paired_pid"
