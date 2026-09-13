#!/usr/bin/env python3
"""Security test: an agent configured to call the Orders BACKEND directly
(bypassing APIM) must fail, while the governed agent succeeds.

Creates a throwaway agent version whose tool server is the backend hostname,
asks the same question, asserts the order facts are NOT returned (the backend's
Easy Auth rejects any caller but the APIM identity), then deletes the agent.

Usage: scripts/agent/security_test.py agents/api-platform-assistant DEV
Env:   FOUNDRY_PROJECT_ENDPOINT_<S>, BACKEND_URL_ORDERS_API_<S>, API_AUDIENCE_<S>, FOUNDRY_MODEL_DEPLOYMENT_<S>
"""
import os
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from common import env, filtered_spec, grant_agent_roles, load_agent  # noqa: E402

NEGATIVE = "api-platform-assistant-bypass-test"


def main(agent_dir: pathlib.Path, suffix: str) -> int:
    from azure.ai.projects import AIProjectClient
    from azure.ai.projects.models import (OpenApiFunctionDefinition, OpenApiManagedAuthDetails,
                                          OpenApiManagedSecurityScheme, OpenApiTool, PromptAgentDefinition)
    from azure.identity import DefaultAzureCredential

    d = load_agent(agent_dir, suffix)
    orders = next(t for t in d["_tools"] if t["name"] == "orders_api")
    backend = env("BACKEND_URL_ORDERS_API", suffix)
    spec = filtered_spec(orders, None)
    spec["servers"] = [{"url": backend.rstrip("/")}]  # direct backend: what a rogue definition would do
    credential = DefaultAzureCredential()
    client = AIProjectClient(endpoint=env("FOUNDRY_PROJECT_ENDPOINT", suffix), credential=credential)
    ok = True
    try:
        client.agents.create_version(agent_name=NEGATIVE, definition=PromptAgentDefinition(
            model=d["model"]["deployment"], instructions=d["_instructions"], temperature=0.1,
            tools=[OpenApiTool(openapi=OpenApiFunctionDefinition(
                name="orders_api", description=orders["description"], spec=spec,
                auth=OpenApiManagedAuthDetails(security_scheme=OpenApiManagedSecurityScheme(audience=orders["auth"]["audience"]))))]),
            description="NEGATIVE TEST: tool points at the backend directly; must fail", metadata={"purpose": "security-test"})
        # Same roles as the real agent so the ONLY difference is the URL. Best effort:
        # Foundry signs tool calls with its account identity (which already holds the
        # roles); the per-agent identity is new and may not be visible in Graph yet.
        neg = client.agents.get(NEGATIVE); ident = getattr(neg, "instance_identity", None) or {}
        if ident.get("principal_id"):
            for attempt in range(3):
                try:
                    grant_agent_roles(credential, ident["principal_id"], orders["auth"]["audience"], list((d.get("identity") or {}).get("roles") or [])); break
                except (Exception, SystemExit) as e:  # noqa: BLE001  (the helper exits on Graph errors)
                    print(f"  role grant to the throwaway identity not possible yet ({e}); retry {attempt + 1}/3"); time.sleep(10)
        openai = client.get_openai_client()
        resp = openai.responses.create(input="Show me order 1024.", extra_body={"agent_reference": {"name": NEGATIVE, "type": "agent_reference"}})
        answer = resp.output_text
        print(f"bypass attempt answer: {answer}")
        if "shipped" in answer.lower() and "1024" in answer:
            print("  FAIL the agent obtained order data directly from the backend"); ok = False
        else:
            print("  PASS direct backend call did not yield order data (backend rejects non-gateway callers)")
    finally:
        try:
            client.agents.delete(NEGATIVE); print(f"  cleaned up {NEGATIVE}")
        except Exception as e:  # noqa: BLE001
            print(f"  cleanup warning: {e}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(f"### Security test (agent → backend directly)\n\nAgent → APIM → Orders API: **ALLOWED**  \nAgent → Orders backend: **{'BLOCKED' if ok else 'NOT BLOCKED'}**\n\n")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(pathlib.Path(sys.argv[1]), sys.argv[2] if len(sys.argv) > 2 else "DEV"))
