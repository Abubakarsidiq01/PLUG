#!/bin/sh
# Drives the whole Phase 1 auth surface against a running backend and prints one line per
# assertion. It is the repeatable version of the checks a reviewer would otherwise do by
# hand with curl, and its output is committed under evidence/P1/logs/.
#
#   docker compose --env-file .env.local up -d --wait postgres
#   cd backend && PLUG_DATABASE_PASSWORD=... PLUG_IDENTITY_PEPPER=... \
#     ./dev bootRun --args='--spring.profiles.active=db --plug.identity.phone-delivery=development'
#   sh tools/phase1-auth-walkthrough.sh
#
# The per-address one-time-code limit is real and is counted in the backend's memory, so a
# second run inside fifteen minutes is refused. That is the control working; restart the
# backend between runs rather than raising the limit.
#
# Phone numbers are unique per run because a number that already has an account is a 409
# by design, and reusing one would make the script fail for the wrong reason.
set -eu
umask 077
WORK=$(mktemp -d "${TMPDIR:-/tmp}/plug-auth.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
RUN=$(python3 -c "import secrets; print(secrets.randbelow(1000000).__format__('06d'))")
num() { echo "+1555${RUN}$1"; }
API=${PLUG_API_URL:-http://127.0.0.1:8080}
# Written by DevelopmentPhoneCodeSender; local only, never a log, never staging.
CODES=${PLUG_DEV_CODES:-backend/build/development-phone-codes.txt}
CONSENT=2026-09-01
pass=0; fail=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s %s\n' "$1" "$3"; pass=$((pass+1));
  else printf '  FAIL  %-58s expected %s got %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
status() { curl --silent --show-error --max-time 20 -o "$WORK/body.json" -w '%{http_code}' "$@"; }
code_for() { awk -v phone="$1" '$2 == phone {code=$NF} END {if (!code) exit 1; print code}' "$CODES"; }
wrong_code() { if [ "$1" = 000000 ]; then echo 000001; else echo 000000; fi; }

echo "=== 1. Guest sign-in ==="
code=$(status -X POST "$API"/v1/auth/guest -H 'Content-Type: application/json' -d "{\"consent_version\":\"$CONSENT\"}")
check "POST /v1/auth/guest" 201 "$code"
GUEST_AT=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['access_token'])")
GUEST_UID=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['account']['user_id'])")
GUEST_SCOPES=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['account']['scopes'])")
check "guest scopes" "['guest']" "$GUEST_SCOPES"

echo "=== 2. Guest reads its own account, is refused session management ==="
check "GET /v1/me" 200 "$(status "$API"/v1/me -H "Authorization: Bearer $GUEST_AT")"
check "GET /v1/me/sessions (guest limit)" 403 "$(status "$API"/v1/me/sessions -H "Authorization: Bearer $GUEST_AT")"
check "  error code" '"forbidden"' "$(python3 -c "import json;print(json.dumps(json.load(open('$WORK/body.json'))['error']['code']))")"

echo "=== 3. Unauthenticated and bad tokens are refused ==="
check "GET /v1/me anonymous" 401 "$(status "$API"/v1/me)"
check "GET /v1/me garbage token" 401 "$(status "$API"/v1/me -H 'Authorization: Bearer pat_nonsense')"
check "GET /v1/me forged jwt" 401 "$(status "$API"/v1/me -H 'Authorization: Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiJhZG1pbiJ9.')"
check "GET /v1/admin/anything" 401 "$(status "$API"/v1/admin/anything)"
check "GET /v1/admin with a real session" 403 "$(status "$API"/v1/admin/anything -H "Authorization: Bearer $GUEST_AT")"

echo "=== 4. Phone verification ==="
check "POST /v1/auth/phone/start" 202 "$(status -X POST "$API"/v1/auth/phone/start -H 'Content-Type: application/json' -d "{\"phone_number\":\"$(num 1)\"}")"
CHALLENGE=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['challenge_id'])")
CODE=$(code_for "$(num 1)")
WRONG_CODE=$(wrong_code "$CODE")
# Captured into its own file so the assertion cannot read another call's body.
WRONG=$(curl --silent --show-error --max-time 20 -o "$WORK/wrong.json" -w '%{http_code}' -X POST "$API"/v1/auth/phone/verify \
  -H 'Content-Type: application/json' \
  -d "{\"challenge_id\":\"$CHALLENGE\",\"code\":\"$WRONG_CODE\",\"consent_version\":\"$CONSENT\"}")
check "wrong code -> validation_failed" 400 "$WRONG"
check "  details[0].code" '"invalid"' "$(python3 -c "import json;print(json.dumps(json.load(open('$WORK/wrong.json'))['error']['details'][0]['code']))")"
check "  error code" '"validation_failed"' "$(python3 -c "import json;print(json.dumps(json.load(open('$WORK/wrong.json'))['error']['code']))")"

echo "=== 5. Guest upgrades in place ==="
code=$(status -X POST "$API"/v1/auth/phone/verify -H 'Content-Type: application/json' -H "Authorization: Bearer $GUEST_AT" -d "{\"challenge_id\":\"$CHALLENGE\",\"code\":\"$CODE\",\"consent_version\":\"$CONSENT\"}")
check "POST /v1/auth/phone/verify with guest token" 201 "$code"
MEM_AT=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['access_token'])")
MEM_RT=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['refresh_token'])")
MEM_UID=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['account']['user_id'])")
check "user_id preserved across upgrade" "$GUEST_UID" "$MEM_UID"
check "account type" '"phone"' "$(python3 -c "import json;print(json.dumps(json.load(open('$WORK/body.json'))['account']['type']))")"
check "old guest token revoked" 401 "$(status "$API"/v1/me -H "Authorization: Bearer $GUEST_AT")"
check "member may list sessions" 200 "$(status "$API"/v1/me/sessions -H "Authorization: Bearer $MEM_AT")"

echo "=== 6. Refresh rotation and replay ==="
check "POST /v1/auth/refresh" 200 "$(status -X POST "$API"/v1/auth/refresh -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$MEM_RT\"}")"
ROT_AT=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['access_token'])")
ROT_RT=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['refresh_token'])")
check "rotated access token differs" "different" "$([ "$ROT_AT" != "$MEM_AT" ] && echo different || echo same)"
check "replaying the spent refresh token" 401 "$(status -X POST "$API"/v1/auth/refresh -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$MEM_RT\"}")"
check "  chain revoked: rotated token also dead" 401 "$(status "$API"/v1/me -H "Authorization: Bearer $ROT_AT")"
check "  chain revoked: rotated refresh also dead" 401 "$(status -X POST "$API"/v1/auth/refresh -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$ROT_RT\"}")"

echo "=== 7. BOLA / IDOR on a resource that takes an id ==="
status -X POST "$API"/v1/auth/phone/start -H 'Content-Type: application/json' -d "{\"phone_number\":\"$(num 2)\"}" >/dev/null
C2=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['challenge_id'])"); K2=$(code_for "$(num 2)")
status -X POST "$API"/v1/auth/phone/verify -H 'Content-Type: application/json' -d "{\"challenge_id\":\"$C2\",\"code\":\"$K2\",\"consent_version\":\"$CONSENT\"}" >/dev/null
A_AT=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['access_token'])")
status "$API"/v1/me/sessions -H "Authorization: Bearer $A_AT" >/dev/null
A_SID=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['sessions'][0]['session_id'])")

status -X POST "$API"/v1/auth/phone/start -H 'Content-Type: application/json' -d "{\"phone_number\":\"$(num 3)\"}" >/dev/null
C3=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['challenge_id'])"); K3=$(code_for "$(num 3)")
status -X POST "$API"/v1/auth/phone/verify -H 'Content-Type: application/json' -d "{\"challenge_id\":\"$C3\",\"code\":\"$K3\",\"consent_version\":\"$CONSENT\"}" >/dev/null
B_AT=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['access_token'])")

check "B reads A's session -> 404 not 403" 404 "$(status "$API"/v1/me/sessions/$A_SID -H "Authorization: Bearer $B_AT")"
check "B deletes A's session -> 404" 404 "$(status -X DELETE "$API"/v1/me/sessions/$A_SID -H "Authorization: Bearer $B_AT")"
check "A's session still alive after the attempt" 200 "$(status "$API"/v1/me -H "Authorization: Bearer $A_AT")"
check "A reads its own session" 200 "$(status "$API"/v1/me/sessions/$A_SID -H "Authorization: Bearer $A_AT")"

echo "=== 8. Consent ==="
check "unpublished consent version refused" 400 "$(status -X POST "$API"/v1/auth/guest -H 'Content-Type: application/json' -d '{"consent_version":"1999-01-01"}')"
check "  field" '"consent_version"' "$(python3 -c "import json;print(json.dumps(json.load(open('$WORK/body.json'))['error']['details'][0]['field']))")"
check "POST /v1/me/consent" 200 "$(status -X POST "$API"/v1/me/consent -H 'Content-Type: application/json' -H "Authorization: Bearer $A_AT" -d "{\"version\":\"$CONSENT\"}")"

echo "=== 9. Logout revokes server-side ==="
check "POST /v1/auth/logout" 204 "$(status -X POST "$API"/v1/auth/logout -H "Authorization: Bearer $A_AT")"
check "access token dead after logout" 401 "$(status "$API"/v1/me -H "Authorization: Bearer $A_AT")"

echo "=== 10. Brute force is stopped ==="
status -X POST "$API"/v1/auth/phone/start -H 'Content-Type: application/json' -d "{\"phone_number\":\"$(num 4)\"}" >/dev/null
C4=$(python3 -c "import json;print(json.load(open('$WORK/body.json'))['challenge_id'])")
WRONG_CODE=$(wrong_code "$(code_for "$(num 4)")")
last=""
for i in 1 2 3 4 5 6; do
  last=$(status -X POST "$API"/v1/auth/phone/verify -H 'Content-Type: application/json' -d "{\"challenge_id\":\"$C4\",\"code\":\"$WRONG_CODE\",\"consent_version\":\"$CONSENT\"}")
done
check "guessing runs out of attempts" 429 "$last"
for i in 1 2 3 4 5; do status -X POST "$API"/v1/auth/phone/start -H 'Content-Type: application/json' -d "{\"phone_number\":\"$(num 5)\"}" >/dev/null; done
check "asking for codes repeatedly is limited" 429 "$(status -X POST "$API"/v1/auth/phone/start -H 'Content-Type: application/json' -d "{\"phone_number\":\"$(num 5)\"}")"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
