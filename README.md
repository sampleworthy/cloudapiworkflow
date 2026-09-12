# cloudapiworkflow — API onboarding on a shared Azure API Management platform

An enterprise pattern for onboarding APIs to **one shared Azure API Management
instance** through Git: an API team adds an OpenAPI document, a metadata file
and a policy file, opens a pull request, and after review the API appears in
the existing gateway. APIM is deployed once; onboarding never recreates it.

```
API team submits                 GitHub                  CI/CD                     Azure
┌──────────────────┐   PR   ┌──────────────┐  merge  ┌────────────────┐  OIDC  ┌─────────────────────────┐
│ apis/orders-api/ │ ─────▶ │ CODEOWNERS   │ ──────▶ │ terraform plan │ ─────▶ │ EXISTING APIM           │
│  api.yaml        │        │ status checks│         │ guard: gateway │        │  ├── skills-api-v1      │
│  openapi.yaml    │        │ plan comment │         │   untouched    │        │  ├── orders-api-v1  NEW │
│  policies/*.xml  │        │ review       │         │ terraform apply│        │  └── customer-api-v1    │
└──────────────────┘        └──────────────┘         └────────────────┘        └─────────────────────────┘
```

## The problem

Organisations with many engineering teams need a standard way to expose APIs
without each team hand-configuring a gateway, and without the platform team
becoming a ticket queue. Manual APIM configuration drifts, is invisible to
review, and does not scale past a handful of APIs. Giving every team its own
APIM instance costs a fortune and fragments policy, identity and monitoring.

## The solution

| principle | how it shows up here |
|---|---|
| **APIM is shared infrastructure** | `terraform/platform` deploys one instance per environment with products, global policy, logging and identity. It changes rarely and only through the platform workflow. |
| **API onboarding has its own Terraform state** | `terraform/api-onboarding` references the instance via remote state outputs and instantiates a reusable `apim-api` module per API with `for_each`. A plan for a new API never contains `azurerm_api_management`, and CI fails if it does. |
| **OpenAPI is the contract** | Every API ships an OpenAPI 3 document that Spectral lints in CI and Terraform imports into APIM. Consumers, reviewers and the gateway read the same file. |
| **Pull request review is API governance** | CODEOWNERS routes each API to its owning team plus the API platform team; the Terraform plan is posted on the PR; the PR template asks about paths, auth, rate limits, versioning and breaking changes. |
| **Modules prevent drift** | Every API is the same module with different inputs, so security policy, diagnostics and product wiring cannot diverge per team. Dev and prod roots are byte-identical apart from tfvars; CI diffs them. |
| **OIDC instead of client secrets** | GitHub Actions federates into per-layer, per-environment Entra identities with least-privilege RBAC. There is no `AZURE_CLIENT_SECRET` anywhere. |
| **Identity and network security** | Callers present Entra client-credentials tokens that APIM validates (issuer, audience, app roles). Backends accept only APIM's managed identity; in prod they are also behind private endpoints. |

## Repository map

```
apis/<name>/                 what an API team owns: api.yaml, openapi.yaml, policies/inbound.xml
applications/<name>/         backend code (FastAPI) for platform-hosted APIs
terraform/bootstrap/         state storage, resource groups, OIDC identities (run once)
terraform/platform/<env>/    the shared platform: APIM, VNet, Key Vault, monitoring, plan
terraform/api-onboarding/<env>/  reads apis/*/api.yaml, adds each API to the existing APIM
terraform/modules/           apim, networking, monitoring, key-vault, app-service, identity, apim-api
.github/workflows/           platform-ci, platform-deploy, api-ci, api-deploy, application-deploy
schemas/api.schema.json      contract for api.yaml     .spectral.yaml   contract for openapi.yaml
scripts/                     onboarding-check, validate-openapi, get-token, test-api
docs/                        architecture, api-onboarding, security, terraform, operations, branch-protection, cost
```

## Onboarding an API in six steps

1. `mkdir apis/orders-api` and add `api.yaml`, `openapi.yaml`, `policies/inbound.xml` (copy from `apis/skills-api` and edit).
2. If the platform hosts the backend, add `applications/orders-api/`.
3. Open a PR. `api-ci` validates the metadata (JSON schema), lints the OpenAPI document (Spectral), checks the policy XML, runs `terraform fmt/validate/plan` against the existing dev instance and posts the plan.
4. Reviewers check the plan: it adds the API, its policy, backend, product link, diagnostic and identity, and **nothing else**.
5. Merge. `api-deploy` authenticates with OIDC, applies, deploys the backend code, and smoke-tests the API through the gateway (health 200, no token 401, valid token 200, direct backend 401).
6. The API is live in the existing instance. Promotion to prod is one line in `terraform/api-onboarding/prod/terraform.tfvars`.

Nothing under `terraform/platform` or `terraform/modules` is touched.
Details: [docs/api-onboarding.md](docs/api-onboarding.md).

## Demonstration: same instance before and after

<!-- evidence:start -->
Before the Orders API pull request:

```
$ az apim api list -g rg-cloudapiworkflow -n apim-cloudapiworkflow-<suffix> -o table
Name           Path         ApiVersion
-------------  -----------  ----------
skills-api-v1  skills       v1
```

After the PR merged (`api-deploy` run, same APIM resource id):

```
$ az apim api list -g rg-cloudapiworkflow -n apim-cloudapiworkflow-<suffix> -o table
Name             Path         ApiVersion
---------------  -----------  ----------
skills-api-v1    skills       v1
orders-api-v1    orders       v1
```

The plan posted on the PR by `api-ci` contained 14 additions, all under
`module.api["orders-api"]`, `module.identity["orders-api"]`,
`module.backend_app["orders-api"]` and the version set, and no change to
`azurerm_api_management`. A third PR added `customer-api` the same way.
<!-- evidence:end -->

## Security architecture in one paragraph

Consumers obtain a Microsoft Entra ID token (client credentials) for the API's
audience `api://<tenant>/<api>-<env>`; APIM validates signature, issuer,
audience and the app roles declared in `api.yaml` (`Skills.Read`,
`Orders.Read`/`Orders.Write`, `Customers.Read`) and applies a per-caller rate
limit. APIM then calls the backend with its **managed identity**; the backend's
built-in authentication accepts only that identity, so the gateway cannot be
bypassed even on the Consumption tier. In production, backends additionally
sit behind private endpoints reachable only from APIM's VNet integration. The
pipelines that deploy all of this use GitHub OIDC with per-layer identities
scoped to `rg-cloudapiworkflow` and to their own state container.
Details: [docs/security.md](docs/security.md).

## Cost-conscious by design

The dev environment runs on **Consumption** APIM and one B1 App Service Plan
for roughly $15-20 a month. The security property that matters (no gateway
bypass) is enforced by identity, so it does not depend on an expensive tier.
Production tfvars select StandardV2 with VNet integration and private
endpoints. See [docs/cost.md](docs/cost.md).

## Getting started (platform administrator)

```bash
# 0. prerequisites: az login (Owner + Application Administrator), terraform 1.16.2, gh
# 1. bootstrap once (creates state storage, rg-cloudapiworkflow, OIDC identities)
cd terraform/bootstrap && terraform init && terraform apply      # see docs/terraform.md for the state migration
# 2. set GitHub variables + environments + ruleset               # docs/branch-protection.md
# 3. run the platform-deploy workflow once                       # creates APIM, VNet, Key Vault, monitoring
# 4. every API from now on is a pull request
```

## Acceptance criteria

| # | criterion | where |
|---|---|---|
| 1 | APIM deployed once as shared platform infrastructure | `terraform/platform`, `modules/apim` (`prevent_destroy`) |
| 2 | Adding an API does not create another APIM | `terraform/api-onboarding` has no `azurerm_api_management`; CI guard |
| 3 | Onboard with OpenAPI + metadata only | `apis/<name>/`; dev needs no Terraform edit |
| 4 | Reusable `apim-api` module | `terraform/modules/apim-api` |
| 5 | `for_each` over data | `locals.tf` discovers `apis/*/api.yaml` |
| 6 | Separate state per layer | `bootstrap`, `platform/<env>`, `api-onboarding/<env>` containers |
| 7 | Validation and plan on PRs | `api-ci`, `platform-ci` |
| 8 | Apply only after merge | `api-deploy`, `platform-deploy` on `push: main` inside environments |
| 9 | OIDC, no long-lived secret | `bootstrap/main.tf` federated credentials; no repository secrets |
| 10 | OpenAPI validated in CI | Spectral + `.spectral.yaml`, `onboarding-check.sh` |
| 11 | Policies in Git | `apis/*/policies/inbound.xml`, `terraform/platform/policies/` |
| 12 | Entra authentication | per-API app registrations + `validate-jwt` |
| 13 | Backends cannot bypass APIM | Easy Auth allow-list of the APIM identity; private endpoints in prod; smoke test asserts 401 |
| 14 | Shared infra not recreated on onboarding | remote state reference, guard, `prevent_destroy` |
| 15 | At least two APIs onboarded | `skills-api`, `orders-api`, `customer-api` |
