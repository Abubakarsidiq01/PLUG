#!/bin/sh
# Simulator evidence for every Phase 2 request state at default and largest Dynamic Type.
# Uses the synthetic fixture server (never live G2 evidence) and writes PNGs to
# evidence/P2/simulator/<date>/. Physical-device captures remain a separate, manual step.
set -eu
cd "$(dirname "$0")/.."

device="${PLUG_SIMULATOR:-iPhone 17 Pro}"
udid=$(xcrun simctl list devices available | sed -nE "s/^ +$device \(([0-9A-F-]+)\).*/\1/p" | head -n 1)
[ -n "$udid" ] || { echo "No available simulator named '$device'. Set PLUG_SIMULATOR." >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/plug-phase2-ui.XXXXXX")
out="evidence/P2/simulator/$(date +%Y-%m-%d)"
server_pid=''
cleanup() { if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; fi; }
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

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
# The synthetic results sit in the Ruston demo zone; a simulator without a location
# reports "unavailable" and the flow takes the address path instead.
# A route that moves a few metres back and forth for about twenty minutes: a fixed point
# keeps its original timestamp, and the app rejects fixes older than two minutes.
route=$(python3 -c "print(' '.join(['32.5280,-92.7140', '32.5282,-92.7142'] * 20))")
# shellcheck disable=SC2086
xcrun simctl location "$udid" start --speed=1 --interval=1 $route >/dev/null

echo "Running request screenshot tests on $device (about ten minutes)."
# Signed for the simulator: an unsigned build has no keychain entitlement, so the
# session cannot be stored and guest sign-in fails before any request screen.
if ! xcodebuild test -project ios/Plug.xcodeproj -scheme PlugUI -destination "id=$udid" \
        -only-testing:PlugUITests/RequestScreenshotTests -resultBundlePath "$work/ui.xcresult" \
        >"$work/xcodebuild.log" 2>&1; then
    grep -E 'error:|Executed [0-9]+ tests' "$work/xcodebuild.log" | tail -6 >&2
    echo "Screenshot tests failed; see $work/xcodebuild.log" >&2
    exit 1
fi
mkdir -p "$out" "$work/attachments"
xcrun xcresulttool export attachments --path "$work/ui.xcresult" --output-path "$work/attachments" >/dev/null
python3 - "$work/attachments" "$out" <<'EOF'
import json, re, shutil, sys
source, target = sys.argv[1], sys.argv[2]
names = set()
for test in json.load(open(f'{source}/manifest.json')):
    for item in test['attachments']:
        match = re.match(r'(synthetic-p2-[a-z-]+)_', item.get('suggestedHumanReadableName', ''))
        if match:
            shutil.copy(f"{source}/{item['exportedFileName']}", f'{target}/{match.group(1)}.png')
            names.add(match.group(1))
print(f'{len(names)} state screenshots written to {target}')
EOF
