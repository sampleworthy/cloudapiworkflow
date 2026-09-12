#!/usr/bin/env python3
"""Compare the APIOps tree in Git (plus the environment's overrides) with what
the extractor pulled from the live APIM instance.

  expected = apim/artifacts  ⊕  rendered configuration.<env>.yaml overrides
  actual   = extractor output folder

JSON artifacts are compared semantically (key order and whitespace ignored,
read-only server fields dropped). Policies are compared after whitespace
normalisation. OpenAPI documents are compared by their operation set (path +
method + operationId) because APIM re-serialises the document on export.

Exit 0 = no drift, 2 = drift (report printed). --copy writes drifted files
from the extractor output over apim/artifacts so a PR can be opened.
"""
import argparse, json, pathlib, re, sys, yaml

IGNORED_KEYS = {"provisioningState", "id", "type", "name", "etag", "isOnline", "subscriptionRequired" }
IGNORED_KEYS.discard("subscriptionRequired")

def load_json(p): return json.load(open(p))
def norm(o):
    if isinstance(o, dict): return {k: norm(v) for k, v in sorted(o.items()) if k not in IGNORED_KEYS and v not in (None, [], {})}
    if isinstance(o, list): return [norm(x) for x in o]
    return o
def deep_merge(a, b):
    out = dict(a)
    for k, v in b.items(): out[k] = deep_merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else v
    return out
def norm_xml(t): return re.sub(r"<!--.*?-->", "", t, flags=re.S).split() and " ".join(re.sub(r"<!--.*?-->", "", t, flags=re.S).split())
def ops(spec_text):
    s = yaml.safe_load(spec_text) or {}
    return sorted(f"{m.upper()} {p} {o.get('operationId','')}" for p, ms in (s.get("paths") or {}).items() for m, o in ms.items() if m in ("get","post","put","patch","delete","head","options"))

def expected_tree(artifacts: pathlib.Path, overrides: dict):
    """Return {relative path: content} with configuration overrides applied."""
    tree = {}
    for f in artifacts.rglob("*"):
        if f.is_file(): tree[f.relative_to(artifacts).as_posix()] = f.read_text()
    section_dirs = {"namedValues": "named values", "loggers": "loggers", "backends": "backends", "diagnostics": "diagnostics",
                    "products": "products", "apis": "apis", "versionSets": "version sets"}
    files = {"named values": "namedValueInformation.json", "loggers": "loggerInformation.json", "backends": "backendInformation.json",
             "diagnostics": "diagnosticInformation.json", "products": "productInformation.json", "apis": "apiInformation.json", "version sets": "versionSetInformation.json"}
    for section, d in section_dirs.items():
        for item in overrides.get(section) or []:
            rel = f"{d}/{item['name']}/{files[d]}"
            if rel in tree and "properties" in item:
                base = json.loads(tree[rel]); base["properties"] = deep_merge(base.get("properties", {}), item["properties"]); tree[rel] = json.dumps(base)
    return tree

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--artifacts", default="apim/artifacts"); ap.add_argument("--extracted", required=True)
    ap.add_argument("--overrides", help="rendered configuration.<env>.yaml"); ap.add_argument("--copy", action="store_true"); a = ap.parse_args()
    art, ext = pathlib.Path(a.artifacts), pathlib.Path(a.extracted)
    overrides = yaml.safe_load(open(a.overrides)) or {} if a.overrides else {}
    expected = expected_tree(art, overrides)
    actual = {f.relative_to(ext).as_posix(): f.read_text() for f in ext.rglob("*") if f.is_file()}
    drift = []
    for rel in sorted(set(expected) | set(actual)):
        if rel not in actual: drift.append(("missing in APIM", rel)); continue
        if rel not in expected: drift.append(("exists in APIM but not in Git", rel)); continue
        e, x = expected[rel], actual[rel]
        if rel.endswith(".json"): same = norm(json.loads(e)) == norm(json.loads(x))
        elif rel.endswith("specification.yaml") or rel.endswith("specification.json"): same = ops(e) == ops(x)
        elif rel.endswith(".xml"): same = norm_xml(e) == norm_xml(x)
        else: same = e.split() == x.split()
        if not same: drift.append(("differs", rel))
    if not drift: print("no APIM configuration drift"); return 0
    print(f"APIM configuration drift: {len(drift)} item(s)")
    for kind, rel in drift: print(f"  {kind:32} {rel}")
    if a.copy:
        for kind, rel in drift:
            src, dst = ext / rel, art / rel
            if kind == "missing in APIM": continue           # Git wins on what should exist; reviewer decides
            dst.parent.mkdir(parents=True, exist_ok=True); dst.write_text(src.read_text())
        print("drifted files copied into", art)
    return 2

if __name__ == "__main__": sys.exit(main())
