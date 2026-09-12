# Architecture

## Platform architecture

One shared API Management instance per environment, owned by the platform
layer. Everything an API needs at runtime (identity, logging, network, secrets)
is shared platform infrastructure; only the API definition itself is per-API.

```mermaid
flowchart TB
    subgraph SUB["Azure subscription"]
        subgraph STATE["rg-cloudapiworkflow-state (bootstrap)"]
            ST["Storage account<br/>Terraform state<br/>containers: bootstrap / platform / api-onboarding"]
            SP1["sp-cloudapiworkflow-platform-{dev,prod}"]
            SP2["sp-cloudapiworkflow-api-{dev,prod}"]
        end
        subgraph RG["rg-cloudapiworkflow (platform)"]
            APIM["API Management<br/>apim-cloudapiworkflow-&lt;suffix&gt;<br/>system-assigned identity"]
            PROD["Products<br/>internal-apis / partner-apis / agent-apis"]
            POL["Global policy + named values"]
            VNET["VNet vnet-cloudapiworkflow<br/>snet-apim / snet-app-integration / snet-private-endpoints"]
            DNS["Private DNS zones<br/>privatelink.azurewebsites.net<br/>privatelink.vaultcore.azure.net"]
            KV["Key Vault<br/>kv-cloudapiworkflow-&lt;suffix&gt;"]
            LAW["Log Analytics<br/>log-cloudapiworkflow"]
            AI["Application Insights<br/>appi-cloudapiworkflow"]
            ASP["App Service Plan<br/>asp-cloudapiworkflow (shared)"]
            AGENT["Entra app<br/>cloudapiworkflow-agent-client"]
            subgraph ONB["added by api-onboarding, per API"]
                API1["skills-api-v1"]
                API2["orders-api-v1"]
                API3["customer-api-v1"]
                WA1["app-skills-api-&lt;suffix&gt;"]
                WA2["app-orders-api-&lt;suffix&gt;"]
                ID1["Entra apps + app roles"]
            end
        end
    end
    APIM --- PROD
    APIM --- POL
    APIM -.-> AI
    AI --- LAW
    ASP --- WA1
    ASP --- WA2
    APIM --> API1 & API2 & API3
    API1 -->|managed identity| WA1
    API2 -->|managed identity| WA2
    WA1 & WA2 -.->|VNet integration| VNET
    VNET --- DNS
```

## Two Terraform layers, three states

| Layer | Root | State key | Owns | Changes |
|---|---|---|---|---|
| bootstrap | `terraform/bootstrap` | `bootstrap/bootstrap.tfstate` | state storage, resource groups, deployer identities, RBAC | once |
| platform | `terraform/platform/<env>` | `platform/<env>.tfstate` | APIM, VNet, DNS, Key Vault, monitoring, App Service Plan, products, global policy, agent client | rarely |
| api-onboarding | `terraform/api-onboarding/<env>` | `api-onboarding/<env>.tfstate` | per API: version set, API, policy, backend, product link, diagnostic, Entra app, web app | every API PR |

The onboarding layer reads the platform through `terraform_remote_state`. The
platform exports a stable contract (`apim_name`, `apim_id`,
`apim_resource_group_name`, `apim_logger_id`, `product_ids`,
`app_service_plan_id`, ...). The onboarding root contains no
`azurerm_api_management` resource, and CI fails any plan in which the gateway
would change.

## API onboarding flow

```mermaid
flowchart TD
    DEV["Developer"] --> F["apis/orders-api/<br/>api.yaml · openapi.yaml · policies/inbound.xml"]
    F --> PR["Pull request<br/>feature/onboard-orders-api"]
    PR --> CI["api-ci<br/>schema check · Spectral · policy XML<br/>terraform fmt / validate / plan"]
    CI --> GUARD{"plan touches<br/>azurerm_api_management?"}
    GUARD -->|yes| FAIL["fail PR"]
    GUARD -->|no| REVIEW["CODEOWNERS review<br/>plan posted on PR"]
    REVIEW --> MERGE["merge to main"]
    MERGE --> DEPLOY["api-deploy<br/>OIDC → terraform apply<br/>zip-deploy backend<br/>smoke tests"]
    DEPLOY --> APIM["EXISTING APIM<br/>apim-cloudapiworkflow-&lt;suffix&gt;"]
    APIM --> E1["skills-api-v1 (existing)"]
    APIM --> E2["orders-api-v1 (new)"]
```

## Runtime security

```mermaid
sequenceDiagram
    participant C as Client / AI agent
    participant E as Microsoft Entra ID
    participant G as APIM (shared gateway)
    participant B as Backend (App Service, Easy Auth)

    C->>E: client_credentials<br/>scope api://tenant/orders-api-dev/.default
    E-->>C: JWT (aud = api://tenant/orders-api-dev, roles = [Orders.Read])
    C->>G: GET /orders/v1/orders<br/>Authorization: Bearer JWT
    Note over G: global policy: correlation id, header hygiene
    Note over G: API policy: validate-jwt (issuer, audience, roles)<br/>rate-limit-by-key (per caller)
    G->>E: token for api://tenant/orders-api-dev<br/>as APIM managed identity
    E-->>G: JWT (appid = APIM identity)
    G->>B: forward + Bearer (APIM identity token)<br/>X-Correlation-Id
    Note over B: Easy Auth: token must be for this app<br/>and from an allowed client (APIM only)
    B-->>G: 200
    G-->>C: 200 + security headers + X-Correlation-Id
    C--xB: direct call to *.azurewebsites.net → 401
```

Detail in [security.md](security.md).

## Policy hierarchy

```
global   (terraform/platform/policies/global.xml)      platform team
  └─ product (terraform/platform/policies/products/*)  platform team
       └─ API (apis/<name>/policies/inbound.xml)       API team, rendered by Terraform
            └─ operation                                (not used; method checks live in the API policy)
```

Every API policy begins with `<base />`, so correlation ids, security headers
and the error shape are inherited, never copied. API policies carry only what
differs per API: audience, roles, rate limit, backend routing, mocking.

## Naming

| Resource | Name |
|---|---|
| Resource group | `rg-cloudapiworkflow` (fixed) |
| APIM | `apim-cloudapiworkflow-<suffix>` |
| Key Vault | `kv-cloudapiworkflow-<suffix>` |
| Web app | `app-<api-name>-<suffix>` |
| Entra resource app | `<Display name> (<env>)`, identifier URI `api://<tenant-id>/<api-name>-<env>` |
| APIM API | `<api-name>-<version>` at `/<path>/<version>` |

`<suffix>` is a 4-character `random_string` created once by the platform layer
and exported so the onboarding layer names web apps consistently.
