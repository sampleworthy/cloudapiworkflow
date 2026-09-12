# Onboarding an API

Adding an API is a pull request that adds one folder. Nothing under
`terraform/` changes for dev; prod needs one line in a tfvars file.

## 1. Create the folder

```
apis/orders-api/
├── api.yaml              metadata (this IS the registration)
├── openapi.yaml          the contract (OpenAPI 3.x)
├── policies/inbound.xml  API policy (starts with <base />)
└── README.md
applications/orders-api/  backend code, only if backend.type is app_service
```

`api.yaml` fields (validated by `schemas/api.schema.json`):

```yaml
name: orders-api            # == folder name, ends with -api
displayName: Orders API
path: orders                # served at /orders/<version>
version: v1                 # APIM version set, Segment scheme
product: internal-apis      # internal-apis | partner-apis | agent-apis
backend:
  type: app_service         # app_service | external | mock
authentication:
  type: entra
  audience: orders-api      # -> api://<tenant-id>/orders-api-<env>
  roles:
    Orders.Read: Read orders
    Orders.Write: Create and update orders
  requiredRoles: [Orders.Read, Orders.Write]   # any-of, read operations
  writeRoles: [Orders.Write]                   # any-of, non-GET operations
  allowedClients: [agent]                      # shared clients granted every role
rateLimit: { calls: 60, renewalPeriod: 60 }
```

Backend types:

| type | what the platform does | who provides the URL |
|---|---|---|
| `app_service` | creates `app-<name>-<suffix>` on the shared plan, Easy Auth locked to APIM's identity; `application-deploy` ships the code | the platform |
| `external` | nothing; APIM forwards to the URL | `backend.url`, or `backend.urlVariable` resolved from `backend_urls` in the environment's tfvars |
| `mock` | APIM returns the OpenAPI examples after validating the token | none (prod usually overrides to `external` through `backend_urls`) |

## 2. Open a pull request

Branch `feature/onboard-orders-api`, fill the PR template. `api-ci` runs:

1. `scripts/onboarding-check.sh` – schema, folder/name match, unique gateway path, roles consistency, policy XML, OpenAPI major version, `/health` present
2. Spectral (`.spectral.yaml`) – OpenAPI 3.x, operationIds, security, 401/429 responses, no backend hosts in `servers`
3. `terraform fmt` / `validate` for both onboarding roots and a check that dev and prod roots are identical
4. `terraform plan` against **dev** with the API deployer identity (OIDC subject `pull_request`)
5. **guard**: the plan is rejected if it changes `azurerm_api_management`
6. The plan is posted on the PR as a comment

## 3. What the plan looks like

For `orders-api` (app_service backend, two roles) the dev plan is:

```
Plan: 12 to add, 0 to change, 0 to destroy.

  + azurerm_api_management_api_version_set.this["orders-api"]
  + module.identity["orders-api"].azuread_application.this
  + module.identity["orders-api"].azuread_service_principal.this
  + module.identity["orders-api"].random_uuid.role["Orders.Read"]
  + module.identity["orders-api"].random_uuid.role["Orders.Write"]
  + module.identity["orders-api"].azuread_app_role_assignment.clients["agent|Orders.Read"]
  + module.identity["orders-api"].azuread_app_role_assignment.clients["agent|Orders.Write"]
  + module.backend_app["orders-api"].azurerm_linux_web_app.this
  + module.backend_app["orders-api"].azurerm_monitor_diagnostic_setting.this[0]
  + module.api["orders-api"].azurerm_api_management_api.this
  + module.api["orders-api"].azurerm_api_management_api_policy.this
  + module.api["orders-api"].azurerm_api_management_backend.this
  + module.api["orders-api"].azurerm_api_management_product_api.this["internal-apis"]
  + module.api["orders-api"].azurerm_api_management_api_diagnostic.this[0]
```

What is **not** there: `azurerm_api_management`, anything in `terraform/platform`,
anything belonging to `skills-api`.

## 4. Review and merge

CODEOWNERS requests the API platform team and the owning API team. Reviewers
check the plan comment against the PR template checklist. Merge to `main`
requires green `api-ci` and the required approvals (see
[branch-protection.md](branch-protection.md)).

## 5. After merge

`api-deploy` runs inside the `development` environment:

1. OIDC login as `sp-cloudapiworkflow-api-dev`
2. `terraform plan` (fresh) + guard + `terraform apply`
3. `application-deploy`: pytest, zip-deploy `applications/orders-api` to `app-orders-api-<suffix>`, wait for `GET /orders/v1/health` through the gateway
4. smoke tests as the agent client (federated, no secret): health 200, no token 401, token 200, direct backend 401
5. lists the APIs now in the shared instance in the job summary

Prod runs the same jobs in the `production` environment (required reviewers)
when `PROD_ENABLED` is set, for the APIs listed in
`terraform/api-onboarding/prod/terraform.tfvars`.

## 6. Result

```
apim-cloudapiworkflow-<suffix>      (same resource id as before the PR)
├── skills-api-v1     /skills/v1
└── orders-api-v1     /orders/v1
```

## Changing an existing API

| change | how |
|---|---|
| non-breaking contract change | edit `openapi.yaml`; APIM re-imports it in place |
| policy change | edit `policies/inbound.xml` |
| new role | add to `authentication.roles` (+ `requiredRoles`/`writeRoles`); the app registration gains the role, the agent client is granted it |
| rate limit | edit `rateLimit` |
| breaking change | new folder `apis/orders-api-v2/` with `versionSet: orders-api`, `version: v2`, `name: orders-api-v2`; v1 stays untouched and both are served |
| retire a version | delete the folder; the plan shows only that version's resources being destroyed |

## Local checks before pushing

```bash
scripts/onboarding-check.sh
scripts/validate-openapi.sh
terraform -chdir=terraform/api-onboarding/dev fmt -check -recursive ../..
(cd applications/orders-api && pip install -r requirements-dev.txt && pytest)
```
