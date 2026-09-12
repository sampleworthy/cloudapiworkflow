# Onboarding, changing and retiring an API

Adding an API is a pull request that adds one folder under `apim/artifacts/apis/`
and a few one-line links. No Terraform runs.

## 1. Add the artifacts

```text
apim/artifacts/apis/orders-api-v1/apiInformation.json                      path, version, version set, revision
apim/artifacts/apis/orders-api-v1/specification.yaml                       OpenAPI 3.x
apim/artifacts/apis/orders-api-v1/policy.xml                               validate-jwt, roles, rate limit, backend
apim/artifacts/apis/orders-api-v1/diagnostics/applicationinsights/diagnosticInformation.json
apim/artifacts/version sets/orders-api/versionSetInformation.json         one per logical API
apim/artifacts/backends/orders-api/backendInformation.json                 named backend (URL overridden per env)
apim/artifacts/products/internal-apis/apis/orders-api-v1/productApiInformation.json   product link ({})
apim/configuration.dev.yaml   +  backends: orders-api url {#BACKEND_URL_ORDERS_API#}
apim/configuration.prod.yaml  +  same
apim/extractor.config.yaml    +  apis: orders-api-v1, backends: orders-api, versionSets: orders-api
apis/orders-api/README.md     owner, lifecycle, how to call
```

Copy `skills-api-v1` and edit. `apiInformation.json` for a versioned API:

```json
{
  "properties": {
    "displayName": "Orders API",
    "description": "Create and query customer orders. Lifecycle: active. Owner: orders-team.",
    "path": "orders",
    "protocols": ["https"],
    "apiVersion": "v1",
    "apiVersionSetId": "/apiVersionSets/orders-api",
    "apiRevision": "1",
    "isCurrent": true,
    "subscriptionRequired": false
  }
}
```

The policy needs only the API's role names; audience and tenant come from
named values. If the API needs a role that does not exist yet, add it to
`api_app_roles` in `terraform/environments/*/terraform.tfvars` in a separate
platform PR first (the platform team owns identity).

## 2. Open a pull request

Branch `feature/onboard-orders-api`, fill the PR template. `api-validation` runs:

1. `scripts/validate-artifacts.sh` – JSON parses; version set, backend and product links resolve; unique gateway path; OpenAPI major version == `apiVersion`; `/health` exists; extractor scope covers the API
2. `scripts/validate-openapi.sh` – Spectral with `governance/.spectral.yaml`
3. `scripts/detect-breaking-changes.sh` – oasdiff against `main` for every changed specification
4. `scripts/validate-policy.sh` – well-formed XML, `<base />`, `validate-jwt` present, no secrets / ids / hostnames
5. gitleaks
6. deletion guard – deleted API folders require the `api-retirement` label

CODEOWNERS requests the owning API team and the API platform team.

## 3. Merge → publish → test

`apiops-publisher` (environment `development`):

1. retirement guard on the merged commit
2. OIDC login as the publisher identity; bearer token for the tool
3. render `configuration.dev.yaml` from repository variables
4. publisher with `COMMIT_ID=<merge sha>`: creates the version set, backend, API, policy, diagnostic and product link in the **existing** instance
5. `scripts/verify-publish.sh`: `az apim api show` confirms path `orders`, version `v1`, revision `1`
6. post-deployment tests as the two demo clients (tokens via federated credentials, no secrets):

| test | expected |
|---|---|
| `GET /orders/v1/health` | 200 |
| `GET /orders/v1/orders`, no token | 401 |
| garbage bearer token | 401 |
| valid token, no roles (unprivileged client) | 403 |
| valid token with `Orders.Read` (agent client) | 200 |
| 70 requests inside the 60/min limit | at least one 429 with `Retry-After` |
| `GET https://app-orders-api-<suffix>.azurewebsites.net/health` (no APIM) | 401 |

7. job summary lists the APIs in the instance and links the App Insights query.

Backend code ships independently through `application-deploy` when
`applications/orders-api/**` changes; the web app itself already exists.

## 4. Promote to production

`api-promote` with the merge SHA. It refuses SHAs without a successful dev
publish, then runs inside the `production` environment (required reviewers)
with `configuration.prod.yaml`. Promotion is by commit; nothing is re-authored.

## Versions vs revisions

| change | mechanism | folder |
|---|---|---|
| non-breaking contract change (new optional field, new operation) | edit `specification.yaml` in place | same |
| policy or configuration change you want to stage | **revision**: copy to `orders-api-v1;rev=2` with `apiRevision: "2"`, `isCurrent: false`; test at `/orders/v1;rev=2/...`; flip `isCurrent` in a second PR | sibling `;rev=2` |
| breaking contract change | **version**: new folder `orders-api-v2` with `apiVersion: "v2"` and the same `apiVersionSetId`; v1 untouched | new |

oasdiff blocks a breaking change to an existing version. A new version folder
has no base to compare, so it passes. Consumers move on their own schedule.

## Retirement

```text
active ──► deprecated (≥ 90 days) ──► retired
```

1. **Deprecate**: PR that prefixes the description with `[DEPRECATED until YYYY-MM-DD]`, adds `Sunset` and `Deprecation` response headers in the API policy's `<outbound>`, and updates `apis/<name>/README.md`. Consumers are notified through the product's subscriber list / the platform changelog.
2. **Retire**: after the date, a PR labelled `api-retirement` deletes `apim/artifacts/apis/<api>/` and the product link. `api-validation` refuses the deletion without the label; `apiops-publisher` refuses to publish a commit that deletes APIs unless the merged PR carried it. Prod retirement additionally passes the `production` environment reviewers via `api-promote`.
3. The version set stays until its last version is gone; the backend entity is removed with the last API that references it.

Nothing is deleted because a file "disappeared": a deletion is a reviewed,
labelled change, and the publisher only deletes in delta mode.

## Local checks

```bash
pip install pyyaml
scripts/validate-artifacts.sh && scripts/validate-policy.sh && scripts/validate-openapi.sh
scripts/detect-breaking-changes.sh origin/main
```
