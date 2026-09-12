#!/usr/bin/env bash
# Smoke-tests every onboarded API through the gateway and proves the backend
# cannot be reached directly.
#
#   1. GET <gateway>/<path>/health            -> 200 (anonymous at the gateway)
#   2. GET <gateway>/<path>/<first operation> -> 401 without a token
#   3. same with a token for the API audience -> 200 (when --token-cmd given)
#   4. GET https://<web-app>/health           -> 401 (Easy Auth blocks bypass)
#
# Usage: scripts/test-api.sh --outputs outputs.json [--token-cmd '<cmd printing a token for $AUDIENCE>'] [--api <dir>]
#   outputs.json = `terraform output -json` from terraform/api-onboarding/<env>
set -euo pipefail

OUTPUTS=""; TOKEN_CMD=""; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --outputs) OUTPUTS="$2"; shift 2;;
    --token-cmd) TOKEN_CMD="$2"; shift 2;;
    --api) ONLY="$2"; shift 2;;
    *) echo "unknown arg $1"; exit 2;;
  esac
done
[ -f "$OUTPUTS" ] || { echo "--outputs file required"; exit 2; }
command -v jq >/dev/null || { echo "jq required"; exit 2; }

GATEWAY=$(jq -r '.apim_gateway_url.value' "$OUTPUTS")
fail=0
check() { # label expected actual
  if [ "$2" = "$3" ]; then echo "  PASS $1 -> $3"; else echo "  FAIL $1 -> $3 (expected $2)"; fail=1; fi
}
get() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@"; }
retry_get() { # url expected -> waits for cold starts / Oryx builds
  local code; for i in $(seq 1 12); do code=$(get "$1"); [ "$code" = "$2" ] && break; sleep 10; done; echo "$code"
}

for key in $(jq -r '.apis.value | keys[]' "$OUTPUTS"); do
  [ -n "$ONLY" ] && [ "$ONLY" != "$key" ] && continue
  url=$(jq -r ".apis.value[\"$key\"].url" "$OUTPUTS")
  audience=$(jq -r ".apis.value[\"$key\"].audience" "$OUTPUTS")
  backend_type=$(jq -r ".apis.value[\"$key\"].backend_type" "$OUTPUTS")
  backend_url=$(jq -r ".apis.value[\"$key\"].backend_url" "$OUTPUTS")
  # first non-health GET path from the spec (path templates -> example values)
  op=$(python3 - "$key" <<'PY'
import sys, yaml, re, pathlib
spec = yaml.safe_load(pathlib.Path(f"apis/{sys.argv[1]}/openapi.yaml").read_text())
for p, ops in spec["paths"].items():
    if p != "/health" and "get" in ops:
        print(re.sub(r"\{[^}]+\}", lambda m: "cust-42" if "customer" in m.group(0) else "ord-1001" if "order" in m.group(0) else "terraform", p)); break
PY
)
  echo "== $key  ($url)"
  check "health via gateway" 200 "$(retry_get "$url/health" 200)"
  check "no token -> 401" 401 "$(get "$url$op")"
  if [ -n "$TOKEN_CMD" ]; then
    token=$(AUDIENCE="$audience" bash -c "$TOKEN_CMD")
    check "with token -> 200" 200 "$(retry_get "$url$op" 200 -H "Authorization: Bearer $token")"
    check "wrong audience token -> 401" 401 "$(get "$url$op" -H "Authorization: Bearer invalid.token.value")"
  fi
  if [ "$backend_type" = "app_service" ]; then
    check "direct backend bypass -> 401" 401 "$(get "$backend_url/health")"
  fi
done
[ $fail -eq 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
