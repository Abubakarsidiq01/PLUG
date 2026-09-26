#!/bin/sh
# Foreground development tunnel; stop with Control-C when phone testing is finished.
set -eu
cd "$(dirname "$0")/.."

curl --fail --silent --max-time 5 http://127.0.0.1:8080/health >/dev/null || {
    echo 'Start tools/run-phase1-local.sh in another terminal first.' >&2
    exit 1
}
log=$(mktemp "${TMPDIR:-/tmp}/plug-phone-tunnel.XXXXXX")
tunnel_pid=''
awake_pid=''
cleanup() {
    trap - EXIT INT TERM
    if [ -n "$tunnel_pid" ]; then kill "$tunnel_pid" 2>/dev/null || true; fi
    if [ -n "$awake_pid" ]; then kill "$awake_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# The bundled version can stall after its optional connectivity diagnostics.
# Our backend and public health probes below check the actual application path.
.tools/cloudflared/cloudflared tunnel --no-prechecks --url http://127.0.0.1:8080 >"$log" 2>&1 &
tunnel_pid=$!
# Prevent idle sleep only during this test session, without changing system settings.
/usr/bin/caffeinate -i -w "$tunnel_pid" &
awake_pid=$!
echo "Tunnel log: $log"
check_public_health() {
    if curl --fail --silent --max-time 3 "$url/health" >/dev/null; then return 0; fi
    # Some Wi-Fi resolvers reject fresh quick-tunnel names. Verify the same HTTPS
    # host through public DNS without changing this Mac's network configuration.
    host=${url#https://}
    address=$(dig +time=2 +tries=1 +short "$host" @1.1.1.1 A | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print; exit }')
    if [ -n "$address" ] && curl --fail --silent --max-time 3 \
        --resolve "$host:443:$address" "$url/health" >/dev/null; then
        echo 'Wi-Fi DNS cannot resolve this tunnel. Test the iPhone over mobile data or another network.'
        return 0
    fi
    return 1
}
attempt=0
while [ "$attempt" -lt 30 ]; do
    kill -0 "$tunnel_pid" 2>/dev/null || { echo "Tunnel stopped; inspect $log" >&2; exit 1; }
    url=$(sed -nE 's/.*(https:\/\/[a-z0-9-]+\.trycloudflare\.com).*/\1/p' "$log" | head -n 1)
    if [ -n "$url" ] && check_public_health; then
        python3 tools/set-phone-api.py "$url"
        echo "Phone API: $url"
        echo 'In Xcode select Plug and your iPhone, then press Command-R.'
        echo 'Keep this terminal and the Mac lid open. Control-C stops the tunnel and sleep prevention.'
        wait "$tunnel_pid"
        exit "$?"
    fi
    attempt=$((attempt + 1))
    sleep 2
done
echo "Tunnel did not become healthy; inspect $log" >&2
exit 1
