#!/usr/bin/env bash
# Post-deployment tests for one API through the gateway, plus backend protection.
#
#   health          GET <gateway>/<path>/<version>/health          -> 200
#   no token        <first operation>                              -> 401
#   invalid token   <first operation> with a garbage bearer        -> 401
#   no permission   <first operation> as the unprivileged client   -> 403
#   authorized      <first operation> as the agent client          -> 200 (or 201)
#   backend bypass  GET https://<backend>/health (no APIM)          -> 401
#
# The "first operation" is the first non-health operation in the contract, any
# method; a POST uses the contract's request example and a query example
# (e.g. api-version) when defined, so model APIs are exercised end to end.
#
# Usage: scripts/smoke-test.sh <api-folder e.g. skills-api-v1>
# Env:   APIM_GATEWAY_URL, AGENT_TOKEN, UNPRIVILEGED_TOKEN, [BACKEND_URL]
set -euo pipefail
API="${1:?api folder name}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
info="$ROOT/apim/artifacts/apis/$API/apiInformation.json"
path=$(python3 -c "import json;p=json.load(open('$info'))['properties'];print(p['path'] + ('/' + p['apiVersion'] if p.get('apiVersion') else ''))")
read -r method op body < <(python3 - "$ROOT/apim/artifacts/apis/$API/specification.yaml" <<'PY'
import sys, yaml, re, json, urllib.parse
spec = yaml.safe_load(open(sys.argv[1]))
for p, ops in spec["paths"].items():
    if p == "/health": continue
    for m in ("get", "post", "put", "patch", "delete"):
        if m not in ops: continue
        o = ops[m]
        def pathval(m2):
            n = m2.group(1)
            for prm in o.get("parameters", []):
                if prm.get("name") == n and prm.get("in") == "path":
                    ex = prm.get("example") or prm.get("schema", {}).get("example")
                    if ex: return str(ex)
            return "cust-42" if "customer" in n else "ord-1001" if "order" in n else "gpt-4.1-mini" if "deploy" in n else "terraform"
        url = re.sub(r"\{([^}]+)\}", pathval, p)
        q = {prm["name"]: str(prm.get("example") or prm.get("schema", {}).get("example", ""))
             for prm in o.get("parameters", []) if prm.get("in") == "query" and prm.get("required")}
        if q: url += "?" + urllib.parse.urlencode(q)
        ex = (o.get("requestBody", {}).get("content", {}).get("application/json", {}) or {}).get("example")
        print(m.upper(), url, json.dumps(ex, separators=(",", ":")) if ex is not None else "-"); sys.exit(0)
print("GET /", "-")
PY
)
base="${APIM_GATEWAY_URL%/}/$path"; fail=0
check() { if [[ " $2 " == *" $3 "* ]]; then echo "  PASS $1 -> $3"; else echo "  FAIL $1 -> $3 (expected $2)"; fail=1; fi; }
get() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@"; }
call() { # <auth header or -> ; runs the first operation with its method/body
  if [ "$body" = "-" ]; then get -X "$method" "$base$op" ${1:+-H "$1"}
  else get -X "$method" "$base$op" -H 'Content-Type: application/json' -d "$body" ${1:+-H "$1"}; fi
}
retry() { local c; for i in $(seq 1 18); do c=$("$@"); [[ " 200 201 " == *" $c "* ]] && break; sleep 10; done; echo "$c"; }
echo "== $API  ($base)  operation: $method $op"
check "health via gateway"              200 "$(retry get "$base/health")"
check "no token"                        401 "$(call)"
check "invalid token"                   401 "$(call 'Authorization: Bearer not.a.token')"
check "valid token, no permission"      403 "$(call "Authorization: Bearer ${UNPRIVILEGED_TOKEN:?}")"
check "authorized"                      "200 201" "$(retry call "Authorization: Bearer ${AGENT_TOKEN:?}")"
if [ -n "${BACKEND_URL:-}" ]; then
check "direct backend bypass (no APIM)" 401 "$(get "${BACKEND_URL%/}/health")"
fi
[ $fail -eq 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
