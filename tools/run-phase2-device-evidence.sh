#!/bin/sh
# Physical-iPhone evidence for every Phase 2 request state at default and largest Dynamic Type.
# Runs RequestScreenshotTests on the paired iPhone against the synthetic fixture server,
# reached through its own HTTPS tunnel (ADR-004), and writes PNGs plus greyscale copies to
# evidence/P2/ios/<date>/. The data is synthetic; the rendering, text sizes, permissions and
# gestures are the real device. Keep the iPhone unlocked with PLUG in front while it runs.
# Requires Developer Mode and Settings > Developer > Enable UI Automation on the iPhone.
set -eu
cd "$(dirname "$0")/.."

work=$(mktemp -d "${TMPDIR:-/tmp}/plug-phase2-device.XXXXXX")
out="evidence/P2/ios/$(date +%Y-%m-%d)"
server_pid=''
tunnel_pid=''
cleanup() {
    for pid in "$tunnel_pid" "$server_pid"; do
        if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
    done
}
trap cleanup EXIT INT TERM

if lsof -nP -iTCP:18084 -sTCP:LISTEN >/dev/null 2>&1; then
    echo 'Port 18084 is occupied; stop the old fixture server so current fixtures are served.' >&2
    exit 1
fi
python3 ios/PlugUITests/Support/request_fixture_server.py >"$work/fixture-server.log" 2>&1 &
server_pid=$!
attempt=0
until curl --fail --silent --max-time 1 http://127.0.0.1:18084/health >/dev/null; do
    attempt=$((attempt + 1)); [ "$attempt" -lt 20 ] || { echo 'Fixture server did not start.' >&2; exit 1; }
    sleep 0.5
done

echo '== Fixture tunnel'
.tools/cloudflared/cloudflared tunnel --no-prechecks --url http://127.0.0.1:18084 >"$work/tunnel.log" 2>&1 &
tunnel_pid=$!
url=''
attempt=0
while [ -z "$url" ]; do
    kill -0 "$tunnel_pid" 2>/dev/null || { echo "Tunnel stopped; see $work/tunnel.log" >&2; exit 1; }
    candidate=$(sed -nE 's/.*(https:\/\/[a-z0-9-]+\.trycloudflare\.com).*/\1/p' "$work/tunnel.log" | head -n 1)
    if [ -n "$candidate" ] && curl --fail --silent --max-time 5 "$candidate/health" >/dev/null 2>&1; then
        url=$candidate
    fi
    attempt=$((attempt + 1)); [ "$attempt" -lt 90 ] || { echo 'Fixture tunnel did not become healthy.' >&2; exit 1; }
    sleep 2
done
echo "Fixture API: $url"

echo '== Paired iPhone'
xcrun devicectl list devices --json-output "$work/devices.json" >/dev/null 2>&1
hardware=$(python3 - "$work/devices.json" <<'EOF'
import json, sys
for d in json.load(open(sys.argv[1]))['result']['devices']:
    hw, conn = d.get('hardwareProperties', {}), d.get('connectionProperties', {})
    if hw.get('platform') == 'iOS' and hw.get('reality') == 'physical' and conn.get('tunnelState') != 'unavailable':
        print(hw['udid']); break
EOF
)
[ -n "$hardware" ] || { echo 'No paired iPhone is reachable. Connect it, unlock it and trust this Mac.' >&2; exit 1; }
team=$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]+).*/\1/p' ios/Plug.xcodeproj/project.pbxproj | head -n 1)
[ -n "$team" ] || { echo 'No DEVELOPMENT_TEAM in the project; set signing in Xcode first.' >&2; exit 1; }

echo '== Screenshot tests on the iPhone (about twenty minutes; keep it unlocked)'
# On a device the embedded development address wins over the test's loopback address,
# so the fixture tunnel is built into this test build only.
if ! xcodebuild test -project ios/Plug.xcodeproj -scheme PlugUI -destination "id=$hardware" \
        -only-testing:PlugUITests/RequestScreenshotTests -resultBundlePath "$work/ui.xcresult" \
        -allowProvisioningUpdates DEVELOPMENT_TEAM="$team" \
        PLUG_DEVELOPMENT_API_URL="$url" PLUG_REQUESTS_V2_ENABLED=YES \
        >"$work/xcodebuild.log" 2>&1; then
    grep -E 'error:|Executed [0-9]+ tests|failed' "$work/xcodebuild.log" | tail -8 >&2
    echo "Device screenshot tests failed; see $work/xcodebuild.log" >&2
    exit 1
fi

mkdir -p "$out/greyscale" "$work/attachments"
xcrun xcresulttool export attachments --path "$work/ui.xcresult" --output-path "$work/attachments" >/dev/null
python3 - "$work/attachments" "$out" <<'EOF'
import json, re, shutil, sys
source, target = sys.argv[1], sys.argv[2]
names = set()
for test in json.load(open(f'{source}/manifest.json')):
    for item in test['attachments']:
        match = re.match(r'synthetic-p2-([a-z-]+)_', item.get('suggestedHumanReadableName', ''))
        if match:
            name = f'device-p2-{match.group(1)}'
            shutil.copy(f"{source}/{item['exportedFileName']}", f'{target}/{name}.png')
            names.add(name)
print(f'{len(names)} device screenshots written to {target}')
EOF
for f in "$out"/*.png; do
    sips -m "/System/Library/ColorSync/Profiles/Generic Gray Profile.icc" "$f" --out "$out/greyscale/$(basename "$f")" >/dev/null
done
echo "Greyscale copies in $out/greyscale. Run tools/run-phase2-phone.sh to put the app back on the live backend."
