#!/usr/bin/env bash
# Validates every apis/<name>/ folder before Terraform ever runs.
#
#   * api.yaml conforms to schemas/api.schema.json
#   * folder name == api.yaml name
#   * openapi.yaml and policies/inbound.xml exist
#   * policy XML is well-formed (APIM policy expressions neutralised first)
#   * gateway paths are unique across all APIs
#   * requiredRoles / writeRoles are declared in roles
#   * OpenAPI major version matches api.yaml version (v1 <-> 1.x.y)
#   * OpenAPI defines GET /health
#
# Usage: scripts/onboarding-check.sh [apis-dir]
# Needs: python3 with pyyaml + jsonschema  (pip install pyyaml jsonschema)
set -euo pipefail

APIS_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/apis}"
SCHEMA="$(cd "$(dirname "$0")/.." && pwd)/schemas/api.schema.json"

python3 - "$APIS_DIR" "$SCHEMA" <<'PY'
import json, re, sys, pathlib
import xml.etree.ElementTree as ET

try:
    import yaml, jsonschema
except ImportError:
    sys.exit("missing python deps: pip install pyyaml jsonschema")

apis_dir = pathlib.Path(sys.argv[1])
schema = json.load(open(sys.argv[2]))
errors, seen_paths, count = [], {}, 0

# APIM policy expressions (@(...) / @{...}) legally contain quotes and angle
# brackets that break XML parsers. Replace attribute expressions with a token
# and expression bodies with a comment so structure can still be checked.
def neutralise(xml: str) -> str:
    xml = re.sub(r'="@\((?:[^"]|"[^"]*")*?\)"', '="EXPR"', xml)                 # attr="@( ... "..." ... )"
    xml = re.sub(r'@\{.*?\}(?=\s*<)', '<!--EXPR-->', xml, flags=re.S)           # element text @{ ... }
    xml = re.sub(r'%\{.*?\}', '', xml)                                          # terraform template directives
    xml = re.sub(r'\$\{[^}]*\}', 'TPL', xml)                                    # terraform template values
    return xml

for api_file in sorted(apis_dir.glob("*/api.yaml")):
    count += 1
    d = api_file.parent
    tag = f"[{d.name}]"
    try:
        cfg = yaml.safe_load(api_file.read_text())
    except Exception as e:
        errors.append(f"{tag} api.yaml is not valid YAML: {e}"); continue
    try:
        jsonschema.validate(cfg, schema)
    except jsonschema.ValidationError as e:
        errors.append(f"{tag} api.yaml schema: {e.message} at {'/'.join(map(str, e.absolute_path)) or '<root>'}"); continue

    if cfg["name"] != d.name:
        errors.append(f"{tag} folder name must equal api.yaml name ({cfg['name']})")

    openapi = d / cfg.get("openapi", "openapi.yaml")
    policy = d / cfg.get("policy", "policies/inbound.xml")
    for f in (openapi, policy):
        if not f.is_file():
            errors.append(f"{tag} missing {f.relative_to(apis_dir)}")
    if policy.is_file():
        try:
            ET.fromstring(neutralise(policy.read_text()))
        except ET.ParseError as e:
            errors.append(f"{tag} policy XML not well-formed: {e}")
        if "<base />" not in policy.read_text() and "<base/>" not in policy.read_text():
            errors.append(f"{tag} policy must inherit the global policy with <base />")

    version = cfg.get("version", "v1")
    path_key = f"{cfg['path']}/{version}"
    if path_key in seen_paths:
        errors.append(f"{tag} gateway path /{path_key} already used by {seen_paths[path_key]}")
    seen_paths[path_key] = d.name

    roles = set(cfg["authentication"].get("roles", {}))
    for key in ("requiredRoles", "writeRoles"):
        undeclared = set(cfg["authentication"].get(key, [])) - roles
        if undeclared:
            errors.append(f"{tag} {key} references undeclared roles: {sorted(undeclared)}")

    if openapi.is_file():
        try:
            spec = yaml.safe_load(openapi.read_text())
            major = str(spec["info"]["version"]).split(".")[0]
            if f"v{major}" != version:
                errors.append(f"{tag} openapi info.version {spec['info']['version']} does not match api.yaml version {version}")
            if "get" not in (spec.get("paths", {}).get("/health") or {}):
                errors.append(f"{tag} openapi must define GET /health")
        except Exception as e:
            errors.append(f"{tag} openapi.yaml unreadable: {e}")

if count == 0:
    errors.append("no apis/*/api.yaml found")
for e in errors:
    print(f"ERROR {e}")
if errors:
    sys.exit(1)
print(f"OK {count} API definition(s) valid: {', '.join(sorted(p.parent.name for p in apis_dir.glob('*/api.yaml')))}")
PY
