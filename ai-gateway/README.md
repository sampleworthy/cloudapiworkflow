# ai-gateway/

The AI Gateway is not a separate component: it is the existing API Management
instance plus a handful of APIOps artifacts. This folder is the map; the
artifacts live where APIOps publishes them so they are versioned, reviewed
and deployed like every other policy.

| concern | artifact | path |
|---|---|---|
| model access through the gateway | API `foundry-models-v1` (`/models/v1`) | `apim/artifacts/apis/foundry-models-v1/` |
| model backend (managed identity) | backend `foundry-models` | `apim/artifacts/backends/foundry-models/` |
| approved deployments | named value `model-deployment` (per-environment override) | `apim/artifacts/named values/model-deployment/` |
| token limits and daily quota per caller | policy fragment `ai-token-governance` | `apim/artifacts/policy fragments/ai-token-governance/policy.xml` |
| token metrics per caller and API | policy fragment `ai-observability` | `apim/artifacts/policy fragments/ai-observability/policy.xml` |
| caller attribution (agents, apps, clients) | global policy `X-Caller-Id` | `apim/artifacts/policy.xml` |
| agent-to-API governance | the ordinary API policies (`validate-jwt`, roles, rate limit) | `apim/artifacts/apis/*/policy.xml` |

Design, capability status (GA vs preview) and the model/MCP governance
model: [docs/ai-gateway.md](../docs/ai-gateway.md). Agent lifecycle and the
end-to-end demo: [docs/agentic-architecture.md](../docs/agentic-architecture.md).
Identity chain: [docs/identity.md](../docs/identity.md).

Why no `policies/` folder here: a second copy of gateway policy outside the
APIOps tree would be a second source of truth. Fragments are the
Microsoft-supported way to share policy across APIs, and they are already in
the tree.
