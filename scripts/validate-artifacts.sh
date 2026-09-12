#!/usr/bin/env bash
# Structural checks on the APIOps artifact tree before publishing:
#   * every *.json parses; every api folder has apiInformation.json + specification.yaml + policy.xml
#   * apiVersionSetId points at an existing version set; product links point at existing apis
#   * gateway path + version is unique; backends referenced by policies exist
#   * openapi info.version major matches apiVersion; GET /health exists
#   * extractor.config.yaml lists every api (so drift detection covers it)
# Usage: scripts/validate-artifacts.sh [apim]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "${1:-$ROOT/apim}" <<'PY'
import json, pathlib, re, sys, yaml
apim = pathlib.Path(sys.argv[1]); art = apim / "artifacts"; errors = []
for f in art.rglob("*.json"):
    try: json.load(open(f))
    except Exception as e: errors.append(f"{f.relative_to(apim)}: invalid JSON: {e}")
version_sets = {p.name for p in (art / "version sets").glob("*/")}
backends = {p.name for p in (art / "backends").glob("*/")}
apis = {p.name: p for p in (art / "apis").glob("*/")}
extractor = yaml.safe_load(open(apim / "extractor.config.yaml")) or {}
paths = {}
for name, d in sorted(apis.items()):
    base = name.split(";rev=")[0]
    for req in ("apiInformation.json", "specification.yaml", "policy.xml"):
        if not (d / req).is_file(): errors.append(f"apis/{name}: missing {req}")
    if not (d / "apiInformation.json").is_file(): continue
    props = json.load(open(d / "apiInformation.json")).get("properties", {})
    vs = props.get("apiVersionSetId", "")
    if vs and vs.rsplit("/", 1)[-1] not in version_sets:
        errors.append(f"apis/{name}: apiVersionSetId {vs} has no folder under 'version sets/'")
    key = f"{props.get('path')}/{props.get('apiVersion', '')}"
    if key in paths and paths[key] != base: errors.append(f"apis/{name}: gateway path /{key} already used by {paths[key]}")
    paths[key] = base
    if (d / "specification.yaml").is_file():
        spec = yaml.safe_load(open(d / "specification.yaml"))
        major = str(spec.get("info", {}).get("version", "0")).split(".")[0]
        if props.get("apiVersion") and f"v{major}" != props["apiVersion"]:
            errors.append(f"apis/{name}: openapi info.version {spec['info']['version']} does not match apiVersion {props['apiVersion']}")
        if "get" not in (spec.get("paths", {}).get("/health") or {}): errors.append(f"apis/{name}: specification must define GET /health")
    if (d / "policy.xml").is_file():
        for b in re.findall(r'backend-id="([^"]+)"', (d / "policy.xml").read_text()):
            if b not in backends: errors.append(f"apis/{name}: policy references backend '{b}' with no folder under 'backends/'")
    if base not in (extractor.get("apis") or []): errors.append(f"apis/{name}: add '{base}' to apim/extractor.config.yaml so drift detection covers it")
for link in (art / "products").glob("*/apis/*/productApiInformation.json"):
    if link.parent.name not in apis: errors.append(f"{link.relative_to(apim)}: links a non-existent api '{link.parent.name}'")
for e in errors: print("ERROR", e)
if errors: sys.exit(1)
print(f"OK {len(apis)} api folder(s), {len(version_sets)} version set(s), {len(backends)} backend(s) consistent")
PY
