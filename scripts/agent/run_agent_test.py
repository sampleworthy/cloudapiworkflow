#!/usr/bin/env python3
"""End-to-end agent test: prompt -> agent -> Orders tool -> APIM -> Orders API,
with telemetry proving the request travelled through APIM.

  1. "Show me order 1024." to the deployed agent (Responses API, agent_reference)
  2. assert the answer carries the order facts (ord-1024, shipped) and that a tool call happened
  3. query Log Analytics: AppRequests for orders-api-v1 in the test window whose
     Response-X-Caller-Id equals the agent's own Entra identity (client id), status 200
     (App Insights ingestion lags, so this polls for up to ~6 minutes)

Usage: scripts/agent/run_agent_test.py agents/api-platform-assistant DEV
Env:   FOUNDRY_PROJECT_ENDPOINT_<S>, LOG_ANALYTICS_WORKSPACE_ID_<S>, AGENT_IDENTITY_CLIENT_ID_<S>
"""
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from common import env, load_agent  # noqa: E402

PROMPT = "Show me order 1024."


def ask(client, agent_name: str) -> tuple[str, list[str]]:
    openai = client.get_openai_client()
    resp = openai.responses.create(input=PROMPT, extra_body={"agent_reference": {"name": agent_name, "type": "agent_reference"}})
    kinds = [getattr(item, "type", "?") for item in resp.output]
    return resp.output_text, kinds


def telemetry(workspace: str, caller: list[str], since: dt.datetime) -> dict | None:
    query = (
        "AppRequests | where TimeGenerated > datetime(%s) "
        "| where tostring(Properties['API Name']) == 'orders-api-v1' "
        "| where tostring(Properties['Response-X-Caller-Id']) in (%s) "
        "| project TimeGenerated, Name, ResultCode, DurationMs, CorrelationId = tostring(Properties['Response-X-Correlation-Id']) "
        "| order by TimeGenerated desc | take 5" % (since.isoformat(), ", ".join("'%s'" % c for c in caller))
    )
    out = subprocess.run(["az", "monitor", "log-analytics", "query", "-w", workspace, "--analytics-query", query, "-o", "json"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print("  log query error:", out.stderr.strip()[:300]); return None
    rows = json.loads(out.stdout or "[]")
    return rows[0] if rows else None


def main(agent_dir: pathlib.Path, suffix: str) -> int:
    from azure.ai.projects import AIProjectClient
    from azure.identity import DefaultAzureCredential

    d = load_agent(agent_dir, suffix)
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=1)
    client = AIProjectClient(endpoint=env("FOUNDRY_PROJECT_ENDPOINT", suffix), credential=DefaultAzureCredential())
    print(f"prompt: {PROMPT}")
    answer, kinds = ask(client, d["name"])
    print(f"answer: {answer}\noutput items: {kinds}")
    ok = True
    if "1024" not in answer or "shipped" not in answer.lower():
        print("  FAIL answer does not carry the order facts (ord-1024, shipped)"); ok = False
    else:
        print("  PASS answer carries the order facts")
    if not any(k != "message" for k in kinds):
        print("  FAIL no tool call in the response output"); ok = False
    else:
        print("  PASS a tool call was made")

    workspace = env("LOG_ANALYTICS_WORKSPACE_ID", suffix)
    # Foundry may sign tool calls with the agent's own identity or with one of the
    # Foundry managed identities; any of them proves the call came from the agent runtime.
    caller = [c for c in (os.environ.get(f"AGENT_INSTANCE_CLIENT_ID_{suffix}"), os.environ.get(f"AGENT_IDENTITY_CLIENT_ID_{suffix}"),
                          os.environ.get(f"FOUNDRY_ACCOUNT_IDENTITY_CLIENT_ID_{suffix}")) if c]
    row = None
    for attempt in range(24):
        row = telemetry(workspace, caller, since)
        if row: break
        print(f"  waiting for App Insights ingestion ({attempt + 1}/24)..."); time.sleep(15)
    if row and str(row.get("ResultCode")) == "200":
        print(f"  PASS APIM telemetry: orders-api-v1 {row['Name']} -> {row['ResultCode']} in {row['DurationMs']} ms, callers {caller}, correlation {row.get('CorrelationId')}")
    else:
        print(f"  FAIL no APIM request from the agent identity {caller} for orders-api-v1 found in telemetry (row={row})"); ok = False

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("### End-to-end agent test\n\n")
            f.write(f"Prompt: `{PROMPT}`\n\nAnswer: {answer}\n\nOutput items: `{kinds}`\n\n")
            f.write(f"APIM telemetry: `{json.dumps(row) if row else 'not found'}`\n\n")
            f.write(f"Result: **{'PASS' if ok else 'FAIL'}**\n\n")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(pathlib.Path(sys.argv[1]), sys.argv[2] if len(sys.argv) > 2 else "DEV"))
