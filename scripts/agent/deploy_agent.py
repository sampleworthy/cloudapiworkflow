#!/usr/bin/env python3
"""Deploy an agent definition to the environment's Foundry project as a new
agent version (Foundry CI/CD). Idempotent: every run creates a version whose
metadata records the git commit, so the deployed state is always traceable.

Usage: scripts/agent/deploy_agent.py agents/api-platform-assistant DEV
Env:   FOUNDRY_PROJECT_ENDPOINT_<SUFFIX>, APIM_GATEWAY_URL_<SUFFIX>, API_AUDIENCE_<SUFFIX>,
       FOUNDRY_MODEL_DEPLOYMENT_<SUFFIX>, GITHUB_SHA (optional)
Auth:  DefaultAzureCredential (GitHub OIDC via azure/login, or az login locally)
"""
import os
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from common import build_sdk_tools, env, grant_agent_roles, load_agent  # noqa: E402


def main(agent_dir: pathlib.Path, suffix: str) -> int:
    from azure.ai.projects import AIProjectClient
    from azure.ai.projects.models import PromptAgentDefinition
    from azure.identity import DefaultAzureCredential

    d = load_agent(agent_dir, suffix)
    gateway = env("APIM_GATEWAY_URL", suffix)
    credential = DefaultAzureCredential()
    client = AIProjectClient(endpoint=env("FOUNDRY_PROJECT_ENDPOINT", suffix), credential=credential)
    definition = PromptAgentDefinition(
        model=d["model"]["deployment"],
        instructions=d["_instructions"],
        temperature=d["model"].get("temperature", 0.1),
        tools=build_sdk_tools(d, gateway),
    )
    version = client.agents.create_version(
        agent_name=d["name"],
        definition=definition,
        description=d.get("description", "").strip(),
        metadata={"commit": os.environ.get("GITHUB_SHA", "local")[:40], "owner": str(d.get("owner", "")), "lifecycle": str(d.get("lifecycle", ""))},
    )
    print(f"deployed agent '{d['name']}' version {version.version} (id {version.id}) with tools "
          f"{[t['name'] for t in d['_tools']]} via {gateway}")

    # Foundry creates a dedicated Entra identity per agent (Entra Agent ID). Tool
    # calls are signed with it, so it - not the project - needs the app roles.
    details = client.agents.get(d["name"])
    identity = getattr(details, "instance_identity", None) or {}
    principal_id, client_id = identity.get("principal_id"), identity.get("client_id")
    if not principal_id:
        raise SystemExit("agent has no instance identity; cannot grant roles")
    roles = list((d.get("identity") or {}).get("roles") or [])
    audience = env("API_AUDIENCE", suffix)
    granted = grant_agent_roles(credential, principal_id, audience, roles)
    print(f"agent identity {client_id}: roles {roles} on {audience} (newly granted: {granted or 'none'})")
    gh_env = os.environ.get("GITHUB_ENV")
    if gh_env:
        with open(gh_env, "a") as f:
            f.write(f"AGENT_INSTANCE_CLIENT_ID_{suffix}={client_id}\n")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(f"### Agent deployed\n\n`{d['name']}` version **{version.version}** → tools {[t['name'] for t in d['_tools']]} through `{gateway}`  \nAgent identity `{client_id}` holds {roles} on `{audience}`\n\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(pathlib.Path(sys.argv[1]), sys.argv[2] if len(sys.argv) > 2 else "DEV"))
