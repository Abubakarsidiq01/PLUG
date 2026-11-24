#!/bin/sh
# Fast iOS test run: one reused, always-booted simulator and one DerivedData per checkout,
# so a rerun pays neither a simulator boot nor a clean build.
#
#   tools/ios-test.sh [unit|ui|all] [Target/Class[/testMethod]]
#
# unit (default) runs PlugTests. ui starts the synthetic fixture server on a free port, runs
# PlugUITests against it and stops it on exit. all runs unit, then ui. The optional second
# argument replaces the mode's default -only-testing filter (not allowed with all).
# PLUG_TEST_SIMULATOR names another simulator (default plug-test).
set -eu
cd "$(dirname "$0")/.."

mode="${1:-unit}"
filter="${2:-}"
case "$mode" in
    unit) schemes=Plug ;;
    ui) schemes=PlugUI ;;
    all) schemes='Plug PlugUI'; [ -z "$filter" ] || { echo 'A test filter needs unit or ui mode.' >&2; exit 2; } ;;
    *) echo "Usage: $0 [unit|ui|all] [Target/Class[/testMethod]]" >&2; exit 2 ;;
esac
start=$(date +%s)
derived="$HOME/Library/Developer/Xcode/DerivedData/plug-$(basename "$PWD")"
results="$derived/plug-results"
mkdir -p "$results"

# The simulator is created once, then left booted between runs: a boot costs 10 to 45 seconds.
sim="${PLUG_TEST_SIMULATOR:-plug-test}"
udid=$(xcrun simctl list devices available | sed -nE "s/^ +$sim \(([0-9A-F-]+)\).*/\1/p" | head -n 1)
[ -n "$udid" ] || udid=$(xcrun simctl create "$sim" "iPhone 17 Pro")
xcrun simctl bootstatus "$udid" -b >/dev/null
# The synthetic results sit in the Ruston demo zone; UI tests also set it again per test.
xcrun simctl location "$udid" set 32.528,-92.714

server=''
trap '[ -z "$server" ] || kill "$server" 2>/dev/null || true' EXIT
trap 'exit 130' INT TERM
case "$mode" in ui|all)
    # The real interpreter, not the python shim; its pid is then the server itself, for the trap.
    py=$(uv run --no-project python -I -c 'import sys; print(sys.executable)')
    port=$("$py" -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
    "$py" ios/PlugUITests/Support/request_fixture_server.py "$port" >"$results/fixture-server-$port.log" 2>&1 &
    server=$!
    attempt=0
    until curl --fail --silent --max-time 1 "http://127.0.0.1:$port/health" >/dev/null; do
        attempt=$((attempt + 1)); [ "$attempt" -lt 50 ] || { echo 'Fixture server did not start.' >&2; exit 1; }
        sleep 0.2
    done
    # xcodebuild hands TEST_RUNNER_X to the test runner as X.
    export TEST_RUNNER_PLUG_FIXTURE_URL="http://127.0.0.1:$port"
    ;;
esac

# Signed ad hoc for the simulator: unsigned, the Keychain tests can only skip.
set -- -project ios/Plug.xcodeproj -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$derived" \
    -skipPackagePluginValidation -quiet COMPILER_INDEX_STORE_ENABLE=NO ONLY_ACTIVE_ARCH=YES \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
status=0
bundles=''
for scheme in $schemes; do
    if [ -n "$filter" ]; then only="$filter"; elif [ "$scheme" = Plug ]; then only=PlugTests; else only=PlugUITests; fi
    bundle="$results/$scheme-$(date +%Y%m%d-%H%M%S).xcresult"
    xcodebuild build-for-testing -scheme "$scheme" "$@"
    # Two runs on one simulator would reinstall the app under each other; the second waits.
    lockf -t 3600 "${TMPDIR:-/tmp}/plug-sim-$udid.lock" xcodebuild test-without-building -scheme "$scheme" "$@" \
        -only-testing:"$only" -parallel-testing-enabled NO -enableCodeCoverage NO -resultBundlePath "$bundle" \
        || status=$?
    bundles="$bundles $bundle"
done

for bundle in $bundles; do
    [ -d "$bundle" ] || { echo "No result bundle at $bundle" >&2; continue; }
    summary="$bundle.summary.json"
    xcrun xcresulttool get test-results summary --path "$bundle" >"$summary"
    count() { plutil -extract "$1" raw -o - "$summary"; }
    echo "$(count result): $(count passedTests) passed, $(count failedTests) failed, $(count skippedTests) skipped. $bundle"
done
echo "Took $(($(date +%s) - start)) s."
exit "$status"
