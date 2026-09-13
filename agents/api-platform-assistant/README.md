# API Platform Assistant

A deliberately simple Microsoft Foundry agent that proves the point of the
platform: an AI agent consumes the same governed APIs as everyone else,
through the same gateway, with its own workload identity, and cannot reach a
backend directly.

| | |
|---|---|
| Lifecycle | **active** |
| Runtime | Microsoft Foundry project `proj-cloudapiworkflow-<env>`, model `gpt-4.1-mini` |
| Identity | its own Entra Agent ID identity (`…-api-platform-assistant-AgentIdentity`); app roles `Skills.Read`, `Orders.Read` declared in `agent.yaml`, granted at deploy |
| Tools | `orders_api` → `/orders/v1`, `skills_api` → `/skills/v1`, both via APIM with managed-identity auth |
| Deployed by | `agent-deploy` (GitHub OIDC → `sp-cloudapiworkflow-agent-deployer-<env>` → new agent version) |
| Owner | ai-platform-team |

```text
User: "Show me order 1024."
  → agent selects orders_api.getOrder(orderId=ord-1024)
  → token for api://<tenant>/cloudapiworkflow-<env> as the project identity
  → APIM: validate-jwt, Orders.Read, rate limit, correlation id, X-Caller-Id
  → Orders backend (Easy Auth: APIM identity only)
  → "Order ord-1024 for cust-7 is shipped, total 499.00 USD."
```

## Files

- `agent-definition/agent.yaml` – name, model, instructions and tool list (tokens for environment values)
- `instructions/system.md` – the system prompt; no URLs, no credentials, no data
- `tools/*.tool.yaml` – one per approved API: which published contract, which gateway path, which operations, managed-identity audience
- `tests/` – unit tests for tool construction and definition validation

## Change process

Edit, open a PR. `agent-ci` validates the definition (schema, instructions
hygiene, tools reference published contracts, gateway-only URLs, no secrets)
and runs the unit tests. After merge, `agent-deploy` creates a new agent
version and runs the end-to-end and security tests in dev. Promotion to prod
uses the same workflow with the `production` environment.
