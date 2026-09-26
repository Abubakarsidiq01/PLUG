#!/bin/sh
# Stops the local PLUG backend and the Gradle daemons behind it. Leaves everything else
# alone — in particular the cloudflared tunnel, which is usually the thing you still want.
#
#   sh tools/stop-backend-local.sh
#
# Processes are found by what is LISTENING on the API ports, never by matching "8080" in a
# command line. A tunnel is started as `cloudflared tunnel --url http://localhost:8080`, so
# a pattern match on the port number would kill the tunnel too. It connects out to 8080; it
# does not listen on it, so the distinction is what keeps this safe.
set -eu

cd "$(dirname "$0")/.."

stopped=0

for port in 8080 8081; do
    pids=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true)
    [ -n "$pids" ] || continue
    for pid in $pids; do
        echo "stopping  : pid $pid listening on $port"
        kill "$pid" 2>/dev/null || true
        stopped=$((stopped + 1))
    done
done

# Give them a moment to shut down cleanly, then insist.
if [ "$stopped" -gt 0 ]; then
    n=0
    while [ "$n" -lt 15 ]; do
        still=$(lsof -nP -iTCP:8080 -sTCP:LISTEN -t 2>/dev/null || true)$(lsof -nP -iTCP:8081 -sTCP:LISTEN -t 2>/dev/null || true)
        [ -n "$still" ] || break
        sleep 1
        n=$((n + 1))
    done
    still=$(lsof -nP -iTCP:8080 -sTCP:LISTEN -t 2>/dev/null || true)$(lsof -nP -iTCP:8081 -sTCP:LISTEN -t 2>/dev/null || true)
    if [ -n "$still" ]; then
        echo "stopping  : $still did not exit on its own, forcing"
        for pid in $still; do kill -9 "$pid" 2>/dev/null || true; done
    fi
else
    echo "backend   : nothing was listening on 8080 or 8081"
fi

# Gradle daemons outlive bootRun and hold file locks. There are two possible homes for
# them: ./dev pins GRADLE_USER_HOME under .tools, while a plain ./gradlew run uses the
# default ~/.gradle. Stopping only one leaves the other's daemon running, so stop both.
echo "gradle    : stopping daemons"
if [ -x backend/dev ]; then
    ./backend/dev --stop >/dev/null 2>&1 || true
fi
if [ -x backend/gradlew ]; then
    (cd backend && env -u GRADLE_USER_HOME ./gradlew --stop >/dev/null 2>&1) || true
fi

echo ""
echo "backend   : stopped"
lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1 \
    && echo "WARNING   : something is still listening on 8080" \
    || echo "ports     : 8080 free"

# Reported, never touched.
tunnels=$(pgrep -fl "cloudflared" 2>/dev/null || true)
if [ -n "$tunnels" ]; then
    echo "tunnel    : left running, as intended —"
    echo "$tunnels" | sed 's/^/            /'
else
    echo "tunnel    : none running"
fi
