#!/usr/bin/env bash
# Post-deployment tests for one API through the gateway, plus backend protection.
#
#   health          GET <gateway>/<path>/<version>/health          -> 200
#   no token        GET <first operation>                          -> 401
#   invalid token   GET <first operation> with a garbage bearer    -> 401
#   no permission   GET <first operation> as the unprivileged client -> 403
#   authorized      GET <first operation> as the agent client      -> 200
#   backend bypass  GET https://<backend>/health (no APIM)          -> 401
#
# Usage: scripts/smoke-test.sh <api-folder e.g. skills-api-v1>
# Env:   APIM_GATEWAY_URL, AGENT_TOKEN, UNPRIVILEGED_TOKEN, [BACKEND_URL]
set -euo pipefail
API="${1:?api folder name}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
info="$ROOT/apim/artifacts/apis/$API/apiInformation.json"
path=$(python3 -c "import json;p=json.load(open('$info'))['properties'];print(p['path'] + ('/' + p['apiVersion'] if p.get('apiVersion') else ''))")
op=$(python3 - "$ROOT/apim/artifacts/apis/$API/specification.yaml" <<'PY'
import sys, yaml, re
spec = yaml.safe_load(open(sys.argv[1]))
for p, ops in spec["paths"].items():
    if p != "/health" and "get" in ops:
        print(re.sub(r"\{[^}]+\}", "x", p)); break
PY
)
base="${APIM_GATEWAY_URL%/}/$path"; fail=0
check() { if [ "$2" = "$3" ]; then echo "  PASS $1 -> $3"; else echo "  FAIL $1 -> $3 (expected $2)"; fail=1; fi; }
get() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@"; }
retry() { local c; for i in $(seq 1 18); do c=$(get "$@"); [ "$c" = "200" ] && break; sleep 10; done; echo "$c"; }
echo "== $API  ($base)"
check "health via gateway"              200 "$(retry "$base/health")"
check "no token"                        401 "$(get "$base$op")"
check "invalid token"                   401 "$(get "$base$op" -H 'Authorization: Bearer not.a.token')"
check "valid token, no permission"      403 "$(get "$base$op" -H "Authorization: Bearer ${UNPRIVILEGED_TOKEN:?}")"
check "authorized"                      200 "$(retry "$base$op" -H "Authorization: Bearer ${AGENT_TOKEN:?}")"
if [ -n "${BACKEND_URL:-}" ]; then
check "direct backend bypass (no APIM)" 401 "$(get "${BACKEND_URL%/}/health")"
fi
[ $fail -eq 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
