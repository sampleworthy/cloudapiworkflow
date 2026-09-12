#!/usr/bin/env bash
# After the publisher runs: confirm each API folder in Git exists in APIM with
# the expected path, version and revision, and that deleted folders are gone.
# Usage: scripts/verify-publish.sh <resource-group> <apim-name> [changed-api-folders...]
set -euo pipefail
RG="${1:?rg}"; APIM="${2:?apim}"; shift 2
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
apis=("$@"); [ ${#apis[@]} -eq 0 ] && apis=($(ls "$ROOT/apim/artifacts/apis"))
fail=0
for a in "${apis[@]}"; do
  id="${a%%;rev=*}"; rev="${a##*;rev=}"; [ "$rev" = "$a" ] && rev=""
  info="$ROOT/apim/artifacts/apis/$a/apiInformation.json"
  if [ ! -f "$info" ]; then
    if az apim api show -g "$RG" -n "$APIM" --api-id "$id" -o none 2>/dev/null; then echo "  FAIL $a still exists in APIM after removal"; fail=1; else echo "  PASS $a removed"; fi; continue
  fi
  want_path=$(python3 -c "import json;print(json.load(open('$info'))['properties']['path'])")
  want_ver=$(python3 -c "import json;print(json.load(open('$info'))['properties'].get('apiVersion',''))")
  want_rev=${rev:-$(python3 -c "import json;print(json.load(open('$info'))['properties'].get('apiRevision','1'))")}
  got=$(az apim api show -g "$RG" -n "$APIM" --api-id "$id${rev:+;rev=$rev}" --query "[path, apiVersion, apiRevision]" -o tsv 2>/dev/null | tr '\t' ' ') || { echo "  FAIL $a not found in $APIM"; fail=1; continue; }
  if [ "$got" = "$want_path $want_ver $want_rev" ]; then echo "  PASS $a -> path=$want_path version=$want_ver revision=$want_rev"; else echo "  FAIL $a -> got '$got', want '$want_path $want_ver $want_rev'"; fail=1; fi
done
exit $fail
