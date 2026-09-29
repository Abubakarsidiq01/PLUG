#!/bin/sh
# Compatibility entrypoint; use the same configured providers and database as phone testing.
set -eu
exec sh "$(dirname "$0")/run-phase1-local.sh" "$@"
