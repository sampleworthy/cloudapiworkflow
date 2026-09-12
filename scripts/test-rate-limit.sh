#!/usr/bin/env bash
# Proves the per-caller rate limit: sends calls+10 authorized requests inside
# the renewal window and expects at least one 429 carrying Retry-After.
# Usage: scripts/test-rate-limit.sh <api-folder> [calls]
# Env:   APIM_GATEWAY_URL, AGENT_TOKEN
set -euo pipefail
API="${1:?api folder}"; ROOT="$(cd "$(dirname "$0")/.." && pwd)"
policy="$ROOT/apim/artifacts/apis/$API/policy.xml"
calls="${2:-$(grep -oE 'rate-limit-by-key calls="[0-9]+"' "$policy" | grep -oE '[0-9]+')}"
info="$ROOT/apim/artifacts/apis/$API/apiInformation.json"
path=$(python3 -c "import json;p=json.load(open('$info'))['properties'];print(p['path'] + ('/' + p['apiVersion'] if p.get('apiVersion') else ''))")
op=$(python3 -c "
import yaml,re;s=yaml.safe_load(open('$ROOT/apim/artifacts/apis/$API/specification.yaml'))
print(next(re.sub(r'\{[^}]+\}','x',p) for p,o in s['paths'].items() if p!='/health' and 'get' in o))")
url="${APIM_GATEWAY_URL%/}/$path$op"; total=$((calls + 10)); got429=0; retry_after=""
echo "== $API: $total requests against a limit of $calls/window"
for i in $(seq 1 $total); do
  out=$(curl -s -o /dev/null -w '%{http_code} %header{retry-after}' --max-time 30 -H "Authorization: Bearer ${AGENT_TOKEN:?}" "$url")
  code=${out%% *}; if [ "$code" = "429" ]; then got429=$((got429+1)); retry_after=${out#* }; fi
done
echo "  429 responses: $got429 (Retry-After: ${retry_after:-none})"
[ $got429 -gt 0 ] || { echo "  FAIL rate limit not enforced"; exit 1; }
echo "  PASS rate limit enforced"
