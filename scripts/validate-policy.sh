#!/usr/bin/env bash
# Validate every APIM policy in the APIOps tree:
#   * well-formed XML (policy expressions neutralised first)
#   * non-global policies inherit with <base />; policy fragments use a <fragment> root
#   * API policies validate a JWT (unless the API is explicitly public)
#   * no secrets, tenant ids, subscription ids or backend hostnames inline
# Usage: scripts/validate-policy.sh [apim/artifacts]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "${1:-$ROOT/apim/artifacts}" <<'PY'
import pathlib, re, sys
import xml.etree.ElementTree as ET
root = pathlib.Path(sys.argv[1]); errors = []
def neutralise(xml):
    xml = re.sub(r'="@\((?:[^"]|"[^"]*")*?\)"', '="EXPR"', xml)            # attr="@( ... )"
    xml = re.sub(r'="@\{(?:[^"]|"[^"]*")*?\}"', '="EXPR"', xml)            # attr="@{ ... }"
    xml = re.sub(r'>\s*@[({].*?[)}]\s*<', '>EXPR<', xml, flags=re.S)       # <el>@( ... )</el>
    return xml
patterns = {
    "client secret / key": re.compile(r'(?i)(client_?secret|api[-_ ]?key|password)\s*[=:]\s*["\']?[A-Za-z0-9+/=_-]{12,}'),
    "guid (tenant/subscription id) - use a named value": re.compile(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'),
    "backend hostname - use a named backend": re.compile(r'https?://[a-z0-9.-]+\.azurewebsites\.net'),
}
for f in sorted(root.rglob("policy.xml")):
    rel = f.relative_to(root); text = f.read_text()
    try:
        ET.fromstring(neutralise(text))
    except ET.ParseError as e:
        errors.append(f"{rel}: not well-formed XML: {e}"); continue
    if rel.parts[0] == "policy fragments":
        if not text.lstrip().startswith("<!--") and "<fragment>" not in text: errors.append(f"{rel}: policy fragments must have a <fragment> root")
        elif "<fragment>" not in text: errors.append(f"{rel}: policy fragments must have a <fragment> root")
    elif rel.parts[0] != "policy.xml" and "<base />" not in text and "<base/>" not in text:
        errors.append(f"{rel}: must inherit the parent policy with <base />")
    if rel.parts[0] == "apis" and "<validate-jwt" not in text and "<!-- public-api -->" not in text:
        errors.append(f"{rel}: API policy has no <validate-jwt>; add one or mark the API with <!-- public-api -->")
    for label, pat in patterns.items():
        for m in pat.finditer(text):
            errors.append(f"{rel}: contains {label}: {m.group(0)[:40]}")
for e in errors: print("ERROR", e)
if errors: sys.exit(1)
print(f"OK {len(list(root.rglob('policy.xml')))} policies valid")
PY
