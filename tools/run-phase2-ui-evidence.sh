#!/bin/sh
# Simulator evidence for every Phase 2 request state at default and largest Dynamic Type.
# Uses the synthetic fixture server (never live G2 evidence) and writes PNGs to
# evidence/P2/simulator/<date>/. Physical-device captures remain a separate step.
# Builds once, then splits the walkthroughs across two simulators of the same model: the
# one named by PLUG_SIMULATOR and a clone of it, made on first use. PLUG_UI_SIMULATORS=1
# runs them all on the first.
set -eu
cd "$(dirname "$0")/.."

device="${PLUG_SIMULATOR:-iPhone 17 Pro}"
udid_of() { xcrun simctl list devices available | sed -nE "s/^ +$1 \(([0-9A-F-]+)\).*/\1/p" | head -n 1; }
udid=$(udid_of "$device")
[ -n "$udid" ] || { echo "No available simulator named '$device'. Set PLUG_SIMULATOR." >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/plug-phase2-ui.XXXXXX")
out="${PLUG_UI_EVIDENCE_DIR:-evidence/P2/simulator/$(date +%Y-%m-%d)}"
suite=PlugUITests/RequestScreenshotTests
# Two shards of about the same length; each walk at one text size is the longest test.
shards="$suite/testRequestStatesLargestText,$suite/testAnsweredPlaceEvidence,$suite/testVisualAskHome,$suite/testAccessibilityAudit
$suite/testRequestStatesDefaultText,$suite/testBusinessProfilesAndHomeCancellation,$suite/testDirectSkillEntryWithoutSuggestions"
if [ -n "${PLUG_UI_TEST_FILTER:-}" ] || [ "${PLUG_UI_SIMULATORS:-2}" = 1 ]; then
    shards="${PLUG_UI_TEST_FILTER:-$suite}"
fi
pids=''
cleanup() { for pid in $pids; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM
# Idle sleep pauses the simulators and the tests time out; hold it off until the script ends.
command -v caffeinate >/dev/null && { caffeinate -i -w $$ & }

if lsof -nP -iTCP:18084 -sTCP:LISTEN >/dev/null 2>&1; then
    echo 'Port 18084 is occupied; stop the old fixture server so current fixtures are served.' >&2
    exit 1
fi
python3 ios/PlugUITests/Support/request_fixture_server.py >"$work/fixture-server.log" 2>&1 &
pids="$!"
attempt=0
until curl --fail --silent --max-time 1 http://127.0.0.1:18084/health >/dev/null; do
    attempt=$((attempt + 1)); [ "$attempt" -lt 20 ] || { echo 'Fixture server did not start.' >&2; exit 1; }
    sleep 0.5
done

# The clone keeps the first simulator's settings (keyboard tips dismissed, location allowed),
# so both shards start from the same state. Cloning needs the source shut down, once.
simulators="$udid"
if [ "$(printf '%s\n' "$shards" | wc -l)" -gt 1 ]; then
    second=$(udid_of "$device PLUG UI 2")
    if [ -z "$second" ]; then
        xcrun simctl shutdown "$udid" 2>/dev/null || true
        second=$(xcrun simctl clone "$udid" "$device PLUG UI 2")
    fi
    simulators="$udid $second"
fi
# The synthetic results sit in the Ruston demo zone; a simulator without a location
# reports "unavailable" and the flow takes the address path instead.
# A route that moves a few metres back and forth for about twenty minutes: a fixed point
# keeps its original timestamp, and the app rejects fixes older than two minutes.
route=$(python3 -c "print(' '.join(['32.5280,-92.7140', '32.5282,-92.7142'] * 20))")
for sim in $simulators; do
    xcrun simctl boot "$sim" 2>/dev/null || true
    xcrun simctl bootstatus "$sim" -b >/dev/null
    # shellcheck disable=SC2086
    xcrun simctl location "$sim" start --speed=1 --interval=1 $route >/dev/null
done

# Signed for the simulator: an unsigned build has no keychain entitlement, so the
# session cannot be stored and guest sign-in fails before any request screen.
echo "Building the UI tests for $device."
xcodebuild build-for-testing -project ios/Plug.xcodeproj -scheme PlugUI -destination "id=$udid" \
    >"$work/build.log" 2>&1 \
    || { grep -E 'error:' "$work/build.log" | head -8 >&2; echo "Build failed; see $work/build.log" >&2; exit 1; }

echo "Running request screenshot tests on $(echo "$simulators" | wc -w | tr -d ' ') simulator(s) (about ten minutes)."
index=0
runs=''
for sim in $simulators; do
    index=$((index + 1))
    only=$(printf '%s\n' "$shards" | sed -n "${index}p" | tr ',' '\n' | sed 's/^/-only-testing:/' | tr '\n' ' ')
    # shellcheck disable=SC2086
    xcodebuild test-without-building -project ios/Plug.xcodeproj -scheme PlugUI -destination "id=$sim" \
        $only -resultBundlePath "$work/ui-$index.xcresult" \
        >"$work/xcodebuild-$index.log" 2>&1 &
    runs="$runs $!"; pids="$pids $!"
done
failed=''
index=0
for run in $runs; do
    index=$((index + 1))
    wait "$run" || failed="$failed $index"
done
if [ -n "$failed" ]; then
    for index in $failed; do grep -E 'error:|Executed [0-9]+ tests' "$work/xcodebuild-$index.log" | tail -6 >&2; done
    echo "Screenshot tests failed; see $work/xcodebuild-*.log" >&2
    exit 1
fi

mkdir -p "$out"
for bundle in "$work"/ui-*.xcresult; do
    mkdir -p "$bundle.attachments"
    xcrun xcresulttool export attachments --path "$bundle" --output-path "$bundle.attachments" >/dev/null
done
python3 - "$out" "$work"/ui-*.xcresult.attachments <<'EOF'
import json, re, shutil, sys
target, sources = sys.argv[1], sys.argv[2:]
names = set()
for source in sources:
    for test in json.load(open(f'{source}/manifest.json')):
        for item in test['attachments']:
            match = re.match(r'(synthetic-p2-[a-z-]+)_', item.get('suggestedHumanReadableName', ''))
            if match:
                shutil.copy(f"{source}/{item['exportedFileName']}", f'{target}/{match.group(1)}.png')
                names.add(match.group(1))
print(f'{len(names)} state screenshots written to {target}')
EOF
