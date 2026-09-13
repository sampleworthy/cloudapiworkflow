#!/usr/bin/env python3
"""Validate an agent definition before it can be merged (agent-ci).

  * agent.yaml has name, model.deployment, instructions, tools; name is kebab-case
  * instructions exist, are short, contain no URLs, hosts or credential-looking strings
  * every tool references an OpenAPI document that APIOps publishes (apim/artifacts/apis/*/specification.yaml)
  * tool gatewayPath equals that API's published path/version
  * allowedOperations exist in the contract and are read-only (GET) unless explicitly flagged
  * auth is managed_identity with an audience token; no keys, no hosts, no direct backend URLs anywhere
Usage: scripts/agent/validate_agent.py agents/api-platform-assistant
"""
import json
import pathlib
import re
import sys

import yaml

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from common import GATEWAY_ONLY, ROOT, SECRET_LIKE, TOKEN, load_agent  # noqa: E402


def main(agent_dir: pathlib.Path) -> int:
    errors: list[str] = []
    d = load_agent(agent_dir, rendered=False)
    name = d.get("name", "")
    if not re.fullmatch(r"[a-z][a-z0-9-]{2,60}", name):
        errors.append("agent.yaml: name must be kebab-case")
    if name != agent_dir.name:
        errors.append(f"agent.yaml: name '{name}' must equal the folder name '{agent_dir.name}'")
    if not d.get("model", {}).get("deployment"):
        errors.append("agent.yaml: model.deployment is required (use the {#FOUNDRY_MODEL_DEPLOYMENT#} token)")
    if d.get("lifecycle") not in ("active", "deprecated", "retired"):
        errors.append("agent.yaml: lifecycle must be active | deprecated | retired")
    instr = d["_instructions"]
    if len(instr) > 6000:
        errors.append("instructions: longer than 6000 characters; keep instructions focused")
    if re.search(r"https?://", instr) or GATEWAY_ONLY.search(instr):
        errors.append("instructions: must not contain URLs or hostnames; tools carry the endpoints")
    if SECRET_LIKE.search(instr):
        errors.append("instructions: contains a credential-looking string")
    if not d["_tools"]:
        errors.append("agent.yaml: at least one tool is required")
    for tool in d["_tools"]:
        f = tool["_file"]
        raw = (agent_dir / f).read_text()
        if GATEWAY_ONLY.search(raw) or re.search(r"https?://", raw):
            errors.append(f"{f}: tools must not contain hosts or URLs; the gateway URL is injected at deploy time")
        if SECRET_LIKE.search(raw):
            errors.append(f"{f}: contains a credential-looking string")
        if tool.get("type") != "openapi":
            errors.append(f"{f}: type must be openapi")
        auth = tool.get("auth") or {}
        if auth.get("type") != "managed_identity" or not TOKEN.fullmatch(str(auth.get("audience", ""))):
            errors.append(f"{f}: auth must be managed_identity with audience \"{{#API_AUDIENCE#}}\"")
        spec_path = ROOT / str(tool.get("spec", ""))
        m = re.fullmatch(r"apim/artifacts/apis/([^/]+)/specification\.yaml", str(tool.get("spec", "")))
        if not m or not spec_path.is_file():
            errors.append(f"{f}: spec must be a published contract under apim/artifacts/apis/<api>/specification.yaml"); continue
        api_dir = spec_path.parent
        info = json.loads((api_dir / "apiInformation.json").read_text())["properties"]
        expected = f"{info['path']}/{info.get('apiVersion', '')}".rstrip("/")
        if tool.get("gatewayPath", "").strip("/") != expected:
            errors.append(f"{f}: gatewayPath '{tool.get('gatewayPath')}' must be '{expected}' (from {api_dir.name}/apiInformation.json)")
        spec = yaml.safe_load(spec_path.read_text())
        ops = {(m2, o.get("operationId")) for p, ms in spec.get("paths", {}).items() for m2, o in ms.items() if m2 in ("get", "post", "put", "patch", "delete")}
        ids = {oid for _, oid in ops}
        for oid in tool.get("allowedOperations") or []:
            if oid not in ids:
                errors.append(f"{f}: allowedOperations '{oid}' not in {api_dir.name} contract")
            elif not tool.get("allowWrites") and any(m2 != "get" and o == oid for m2, o in ops):
                errors.append(f"{f}: '{oid}' is not a GET; agents are read-only unless allowWrites: true is reviewed")
    for e in errors:
        print("ERROR", e)
    if errors:
        return 1
    print(f"OK agent '{name}': {len(d['_tools'])} tool(s), all referencing published contracts through the gateway")
    return 0


if __name__ == "__main__":
    sys.exit(main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "agents/api-platform-assistant")))
