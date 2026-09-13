"""Shared helpers for the agent lifecycle scripts (Foundry CI/CD).

Reads the declarative definition under agents/<name>/, renders {#TOKEN#}
placeholders from environment variables (GitHub repository variables written
by terraform-deploy, suffixed _DEV / _PROD), and builds SDK tool objects from
the APIOps-published OpenAPI documents.
"""
from __future__ import annotations

import copy
import os
import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOKEN = re.compile(r"\{#([A-Z0-9_]+)#\}")
GATEWAY_ONLY = re.compile(r"azurewebsites\.net|localhost|127\.0\.0\.1|\d+\.\d+\.\d+\.\d+")
SECRET_LIKE = re.compile(r"(?i)(client_?secret|api[-_ ]?key|password|bearer\s+[A-Za-z0-9._-]{20,})")


def render(text: str, suffix: str | None) -> str:
    missing: list[str] = []

    def sub(m: re.Match) -> str:
        name = m.group(1)
        for key in ([f"{name}_{suffix}"] if suffix else []) + [name]:
            if os.environ.get(key):
                return os.environ[key]
        missing.append(name)
        return m.group(0)

    out = TOKEN.sub(sub, text)
    if missing:
        raise SystemExit(f"unresolved tokens {sorted(set(missing))}; expected variables like {missing[0]}_{suffix or 'ENV'}")
    return out


def load_agent(agent_dir: pathlib.Path, suffix: str | None = None, rendered: bool = True) -> dict:
    text = (agent_dir / "agent-definition" / "agent.yaml").read_text()
    definition = yaml.safe_load(render(text, suffix) if rendered else text)
    definition["_dir"] = agent_dir
    definition["_instructions"] = (agent_dir / definition["instructions"]).read_text()
    tools = []
    for rel in definition.get("tools", []):
        ttext = (agent_dir / rel).read_text()
        tool = yaml.safe_load(render(ttext, suffix) if rendered else ttext)
        tool["_file"] = rel
        tools.append(tool)
    definition["_tools"] = tools
    return definition


def filtered_spec(tool: dict, gateway_url: str | None) -> dict:
    """The published OpenAPI document, reduced to the allowed operations, with
    the gateway as its only server. Security schemes are removed because the
    Foundry tool supplies authentication itself (managed identity)."""
    spec = copy.deepcopy(yaml.safe_load((ROOT / tool["spec"]).read_text()))
    allowed = set(tool.get("allowedOperations") or [])
    paths = {}
    for path, ops in spec.get("paths", {}).items():
        kept = {m: o for m, o in ops.items() if m in ("get", "post", "put", "patch", "delete") and (not allowed or o.get("operationId") in allowed)}
        for o in kept.values():
            o.pop("security", None)
        if kept:
            paths[path] = kept
    spec["paths"] = paths
    spec.pop("security", None)
    spec.get("components", {}).pop("securitySchemes", None)
    if gateway_url:
        spec["servers"] = [{"url": f"{gateway_url.rstrip('/')}/{tool['gatewayPath'].strip('/')}"}]
    else:
        spec.pop("servers", None)
    return spec


def build_sdk_tools(definition: dict, gateway_url: str):
    from azure.ai.projects.models import (OpenApiFunctionDefinition, OpenApiManagedAuthDetails,
                                          OpenApiManagedSecurityScheme, OpenApiTool)
    tools = []
    for tool in definition["_tools"]:
        if tool["auth"]["type"] != "managed_identity":
            raise SystemExit(f"{tool['_file']}: only managed_identity auth is allowed")
        tools.append(OpenApiTool(openapi=OpenApiFunctionDefinition(
            name=tool["name"],
            description=tool["description"],
            spec=filtered_spec(tool, gateway_url),
            auth=OpenApiManagedAuthDetails(security_scheme=OpenApiManagedSecurityScheme(audience=tool["auth"]["audience"])),
        )))
    return tools


def env(name: str, suffix: str | None = None) -> str:
    for key in ([f"{name}_{suffix}"] if suffix else []) + [name]:
        if os.environ.get(key):
            return os.environ[key]
    sys.exit(f"missing environment variable {name}{'_' + suffix if suffix else ''}")
