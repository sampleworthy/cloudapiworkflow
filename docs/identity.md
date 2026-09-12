# Identity

Every hop in the platform authenticates with Microsoft Entra ID and, wherever
Azure talks to Azure, with a managed identity. There are no keys: APIM, the
backends, Foundry and the pipelines all run key-less.

## The chain

```mermaid
flowchart LR
    U["User<br/>(person, signed in to the application)"] -->|user token| APP["Application"]
    APP -->|calls the agent<br/>(Azure AI User on the project)| AG["Foundry agent<br/>project managed identity"]
    AG -->|token for api://tenant/cloudapiworkflow-env<br/>roles: Orders.Read, Skills.Read| GW["APIM"]
    GW -->|token as APIM managed identity<br/>same audience| BE["Backend<br/>Easy Auth: only APIM"]
    GW -->|token as APIM managed identity<br/>audience cognitiveservices| MDL["Foundry model"]
```

| identity | kind | what it proves | granted by |
|---|---|---|---|
| user | person | who is asking; what the application may do for them | the application's own Entra registration and scopes |
| agent / workload | Foundry project system-assigned managed identity | which agent is calling and which APIs it may read | Terraform: app-role assignments `agent_app_roles` |
| APIM | APIM system-assigned managed identity | that the request passed the gateway | Terraform: Easy Auth allow-list on backends; `Cognitive Services OpenAI User` on Foundry |
| backend | web app system-assigned managed identity | access to Key Vault | Terraform: Key Vault Secrets User |
| pipelines | four federated identities per environment | which workflow, in which GitHub environment | bootstrap: federated credentials + RBAC |

## User identity vs agent identity

The agent is a shared workload: many users, one identity. Its permissions are
therefore the **union of what any user may obtain through it**, which is why
its roles are read-only and narrow. The user's identity does not reach APIM
today: Foundry Agent Service authenticates OpenAPI tools with the project
identity and does not perform on-behalf-of exchanges for tool calls.

Consequences the design accepts and documents:

* authorization at the gateway is per agent, not per user
* data the agent can read is data every authorized user of the agent can read
* per-user audit needs the application to log which user triggered which agent run (the run id is in the application's own telemetry)

## Propagating user authorization through an agent

When an API must return data scoped to the authenticated user, two supported
patterns, in order of preference:

1. **Delegated-scope APIs stay with the application.** The application calls user-scoped APIs with the user's own token (audience `api://…/cloudapiworkflow-<env>`, delegated scope) and gives the agent the results as context. The agent's tools are limited to data that is not user-scoped. This keeps the agent identity narrow and needs no new trust.
2. **Asserted user context, gateway-enforced.** The application passes the user's object id (or a signed assertion) as a tool input; the API policy accepts `X-On-Behalf-Of` only when the caller (`azp`) is a known agent identity, forwards it to the backend, logs it, and the backend applies the user filter. Terraform lists the agent client ids the policy trusts (named value `trusted-agent-ids`). This is a *claim of context*, not a user token; it must never widen the agent's own roles.

Full on-behalf-of (the agent exchanging the user's token for an API token) is
documented as the target once Foundry supports user-delegated tool
authentication; the policy shape above then swaps the header check for
`validate-jwt` on the delegated token.

## Pipeline identities

| identity | subjects | rights |
|---|---|---|
| `sp-cloudapiworkflow-platform-<env>` | `environment:<env>`, `pull_request` (dev) | Contributor + UAA on the group; state container; Graph app management |
| `sp-cloudapiworkflow-apiops-publisher-<env>` | `environment:<env>` | API Management Service Contributor + Reader |
| `sp-cloudapiworkflow-apiops-extractor-<env>` | `ref:refs/heads/main`, `environment:<env>` | API Management Service Reader Role + Reader |
| `sp-cloudapiworkflow-agent-deployer-<env>` | `environment:<env>` | Azure AI Developer on the Foundry account; Log Analytics Reader; Reader on the group |

The agent deployer cannot touch APIM, Key Vault or Terraform state; APIOps
identities cannot touch Foundry. Every identity's only credential is a
federated credential for a specific GitHub environment.

## Demo clients

`agent` (roles `Skills.Read`, `Orders.Read`, `Models.Use`) and `unprivileged`
(no roles) are federated for CI and hold a Key Vault secret for local
scripts. They stand in for applications; the Foundry project identity is the
real agent identity and holds only `Skills.Read` and `Orders.Read`.
