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
| agent / workload | today: the Foundry **account**'s system-assigned managed identity (observed as `azp` at APIM on 2026-09-13); Foundry also creates a per-agent Entra Agent ID identity (`<account>-<project>-<agent>-AgentIdentity`, type ServiceIdentity) | which Foundry account (and, once Foundry uses it for tool auth, which agent) is calling, and which APIs it may read | Terraform grants `agent_app_roles` to the account and project identities; `agent-deploy` grants the roles declared in `agent.yaml` (`identity.roles`, allow-listed in `governance/agent-roles.yaml`) to the agent's own identity |
| APIM | APIM system-assigned managed identity | that the request passed the gateway | Terraform: Easy Auth allow-list on backends; `Cognitive Services OpenAI User` on Foundry |
| backend | web app system-assigned managed identity | access to Key Vault | Terraform: Key Vault Secrets User |
| pipelines | four federated identities per environment | which workflow, in which GitHub environment | bootstrap: federated credentials + RBAC |

## User identity vs agent identity

Foundry provisions an Entra Agent ID identity per agent, but as of
2026-09-13 OpenAPI tool calls arrive at APIM signed by the Foundry
**account** managed identity (verified through the gateway's `X-Caller-Id`
attribution). In this platform that identity is shared by every agent in the
account, so its permissions are the **union of what any user of any agent
may obtain**, which is why they are read-only, narrow, and set by the platform
team in Terraform. The per-agent identities are granted their declared roles
by `agent-deploy` so that the day Foundry signs tool calls with them, the
authorization model becomes per agent without a platform change. The user's
identity does not reach APIM today: Foundry does not perform on-behalf-of
exchanges for tool calls.

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
| `sp-cloudapiworkflow-agent-deployer-<env>` | `environment:<env>` | Foundry User on the Foundry account; Log Analytics Reader; Reader on the group; Graph `Application.Read.All` + `AppRoleAssignment.ReadWrite.All` to grant agent identities their declared roles |

The agent deployer cannot touch APIM, Key Vault or Terraform state; APIOps
identities cannot touch Foundry. Every identity's only credential is a
federated credential for a specific GitHub environment.

## Demo clients

`agent` (roles `Skills.Read`, `Orders.Read`, `Models.Use`) and `unprivileged`
(no roles) are federated for CI and hold a Key Vault secret for local
scripts. They stand in for applications; the Foundry project identity is the
real agent identity and holds only `Skills.Read` and `Orders.Read`.
