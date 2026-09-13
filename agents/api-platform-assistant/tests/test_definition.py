import os
import pathlib
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "agent"))
import common  # noqa: E402
import validate_agent  # noqa: E402

AGENT = ROOT / "agents" / "api-platform-assistant"


def test_definition_validates():
    assert validate_agent.main(AGENT) == 0


def test_tools_reference_published_contracts_only():
    d = common.load_agent(AGENT, rendered=False)
    for tool in d["_tools"]:
        assert tool["spec"].startswith("apim/artifacts/apis/")
        assert (ROOT / tool["spec"]).is_file()
        assert tool["auth"]["type"] == "managed_identity"


def test_filtered_spec_is_read_only_and_gateway_bound():
    d = common.load_agent(AGENT, rendered=False)
    orders = next(t for t in d["_tools"] if t["name"] == "orders_api")
    spec = common.filtered_spec(orders, "https://gateway.example/")
    assert spec["servers"] == [{"url": "https://gateway.example/orders/v1"}]
    methods = {m for ops in spec["paths"].values() for m in ops}
    assert methods == {"get"}, "agent tools must be read-only"
    assert "securitySchemes" not in spec.get("components", {})
    assert "/orders/{orderId}" in spec["paths"]


def test_tokens_render_from_environment(monkeypatch):
    monkeypatch.setenv("API_RESOURCE_APP_CLIENT_ID_DEV", "11111111-2222-3333-4444-555555555555")
    monkeypatch.setenv("FOUNDRY_MODEL_DEPLOYMENT_DEV", "gpt-4.1-mini")
    d = common.load_agent(AGENT, "DEV")
    assert d["model"]["deployment"] == "gpt-4.1-mini"
    assert d["_tools"][0]["auth"]["audience"] == "11111111-2222-3333-4444-555555555555"


def test_missing_token_fails_loudly(monkeypatch):
    for k in list(os.environ):
        if k.startswith(("API_RESOURCE_APP_CLIENT_ID", "FOUNDRY_MODEL_DEPLOYMENT")):
            monkeypatch.delenv(k)
    with pytest.raises(SystemExit):
        common.load_agent(AGENT, "DEV")
