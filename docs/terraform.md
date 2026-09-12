# Terraform

Terraform owns the Azure platform and nothing inside API Management.

## Layout

```text
terraform/
├── bootstrap/                run once by a human: state storage, resource groups, OIDC identities, RBAC
├── modules/
│   ├── apim/                 the APIM SERVICE only (SKU, identity, network, TLS, resource logs)
│   ├── networking/           VNet, subnets, NSG, private DNS zones
│   ├── key-vault/            RBAC-mode vault, optional private endpoint
│   ├── monitoring/           Log Analytics + Application Insights
│   ├── identity/             Entra resource app with app roles + client grants
│   └── app-service/          backend web app with Easy Auth locked to APIM's identity
└── environments/{dev,prod}/  composition; identical apart from terraform.tfvars and backend.tf
```

Every module has typed, described, validated variables and explicit outputs.
No resource id is hard-coded; environment roots wire modules together and
tfvars carry the values.

## What the environment root creates

| resource | why |
|---|---|
| `rg-cloudapiworkflow` | imported from bootstrap through a config-driven `import` block (no-op after the first run) |
| VNet, three subnets, NSG, two private DNS zones | dev integration; prod private endpoints |
| Log Analytics, Application Insights | central telemetry; App Insights connection string written to Key Vault for the APIOps logger |
| Key Vault (RBAC mode) | the only place secrets live; APIM identity and backend identities get Secrets User |
| APIM service | `prevent_destroy`; SKU and VNet mode from tfvars |
| App Service Plan + one web app per `backend_apps` entry | demo backends, Easy Auth allow-list = APIM identity, tagged `api=<name>` |
| Entra resource app + app roles (`api_app_roles`) | the token audience every API policy validates |
| demo clients `agent`, `unprivileged` | federated for CI, secret in Key Vault for local use; roles from `demo_clients` |

Outputs include everything APIOps and the workflows need; `github_variables`
is written to repository variables by `terraform-deploy` so nothing else reads
state.

## Remote state

| state | container / key | writer |
|---|---|---|
| bootstrap | `bootstrap/bootstrap.tfstate` (migrated from local after first apply) | platform administrator |
| platform dev | `platform/dev.tfstate` | `sp-cloudapiworkflow-platform-dev` |
| platform prod | `platform/prod.tfstate` | `sp-cloudapiworkflow-platform-prod` |

Storage account `stcawstate4k7m` in `rg-cloudapiworkflow-state`: shared-key
auth disabled (`use_azuread_auth = true` everywhere), TLS 1.2, HTTPS only, no
public blobs, blob versioning and 30-day soft delete, private containers.
RBAC is per container; the APIOps identities have no access at all. There is
deliberately no API-onboarding state: APIOps compares Git with APIM directly.

The account name is chosen up front (`state_storage_account_name`) because
`backend` blocks cannot read variables and every `backend.tf` must contain
the literal. APIM, Key Vault and web apps use Terraform-generated suffixes.

Locking uses blob leases; deploy jobs run in a per-root `concurrency` group
with `-lock-timeout=5m`.

## Deployment safeguards

* `prevent_destroy` on the APIM service and the resource group.
* The composite action inspects the plan JSON and fails if it would delete or replace `azurerm_api_management`, `azurerm_virtual_network`, `azurerm_key_vault`, `azurerm_storage_account` or `azurerm_resource_group`, unless the run sets `ALLOW_DESTRUCTIVE=true` (an explicit, approved migration).
* Prod applies run inside the `production` environment (required reviewers, wait timer) and only when `PROD_ENABLED=true`.
* `terraform-ci` checks that the dev and prod roots are byte-identical apart from tfvars and backend, so drift between environments can only be a value, never code.
* Trivy scans configuration for HIGH/CRITICAL misconfigurations; gitleaks scans for secrets.

## First-time setup

```bash
# 1. bootstrap (local state, then migrate into the account it created)
cd terraform/bootstrap
printf 'terraform { backend "local" {} }\n' > backend_override.tf
terraform init && terraform apply
rm backend_override.tf
terraform init -migrate-state \
  -backend-config=resource_group_name=rg-cloudapiworkflow-state \
  -backend-config=storage_account_name=stcawstate4k7m \
  -backend-config=container_name=bootstrap \
  -backend-config=key=bootstrap.tfstate \
  -backend-config=use_azuread_auth=true
terraform output -raw github_variables | bash     # publishes identity ids as GitHub variables

# 2. GitHub environments + ruleset (docs/branch-protection.md)
# 3. run terraform-deploy (workflow_dispatch) -> platform, once per environment
# 4. run apiops-publisher (workflow_dispatch, mode=full) -> seeds the instance from apim/artifacts
```

## Versions

Terraform `1.16.2` (`.terraform-version`, pinned in CI); `required_version = ">= 1.16.0, < 2.0.0"`.
Providers: `azurerm ~> 4.0`, `azuread ~> 3.0`, `random ~> 3.6`, `time ~> 0.12`.
Lock files are committed per root and CI runs `init -lockfile=readonly`.

## Changing APIM without touching APIs

A SKU or networking change (`apim_sku_name`, `apim_vnet_integration`,
`enable_private_endpoints`) is a platform PR that updates the service in
place. APIOps artifacts are unaffected. Anything that would replace the
instance is blocked by the guard and by `prevent_destroy` until it is planned
as an explicit migration (new instance, full publish, cut-over, retire old).
