# Terraform

## Layout

```
terraform/
├── bootstrap/          run once by a human: state storage, resource groups, OIDC identities, RBAC
├── modules/
│   ├── networking/     VNet, subnets, NSG, private DNS zones
│   ├── monitoring/     Log Analytics + Application Insights
│   ├── key-vault/      RBAC-mode vault, optional private endpoint
│   ├── apim/           the shared instance: products, global policy, named values, logger, diagnostics
│   ├── app-service/    one backend web app with Easy Auth locked to APIM
│   ├── identity/       one Entra resource app with app roles + client grants
│   └── apim-api/       one API inside the existing instance
├── platform/{dev,prod}/        composition of networking/monitoring/key-vault/apim + plan + agent client
└── api-onboarding/{dev,prod}/  discovers apis/*/api.yaml, instantiates identity/app-service/apim-api per API
```

Environment roots (`dev`, `prod`) are byte-identical except `terraform.tfvars`
and `backend.tf`. CI diffs them (`roots-in-sync`) so an environment can never
drift in code, only in values.

## State

| state | backend | who writes |
|---|---|---|
| `bootstrap/bootstrap.tfstate` | local on first run, then migrated to the storage account | platform administrator |
| `platform/dev.tfstate`, `platform/prod.tfstate` | `stcawstate4k7m` / container `platform` | `sp-cloudapiworkflow-platform-<env>` |
| `api-onboarding/dev.tfstate`, `api-onboarding/prod.tfstate` | `stcawstate4k7m` / container `api-onboarding` | `sp-cloudapiworkflow-api-<env>` |

Why the state account name is fixed rather than random: `backend` blocks
cannot read variables, so every `backend.tf` must contain the literal name.
Bootstrap takes it as `state_storage_account_name`; APIM, Key Vault and web
apps use Terraform-generated suffixes because nothing needs to reference them
statically.

### RBAC on the state account

* `shared_access_key_enabled = false`, `use_azuread_auth = true` in every backend: only Entra identities can read or write state.
* One container per layer so roles can be scoped:
  * platform deployer: Storage Blob Data Contributor on `platform`
  * API deployer: Storage Blob Data Contributor on `api-onboarding`, Storage Blob Data **Reader** on `platform` (needed by `terraform_remote_state`)
  * bootstrap operator: Storage Blob Data Contributor on `bootstrap`
* Blob versioning and 30-day soft delete for state recovery.
* Platform state carries sensitive outputs (App Insights connection string); read access to the `platform` container is therefore limited to the API deployer and platform administrators.

### Locking

The azurerm backend uses blob leases. Deploy jobs use a per-root
`concurrency` group so two applies on the same root never overlap, and
`-lock-timeout=5m` for the rare case a lease is held.

## How the onboarding layer finds the platform

```hcl
data "terraform_remote_state" "platform" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-cloudapiworkflow-state"
    storage_account_name = "stcawstate4k7m"
    container_name       = "platform"
    key                  = "${var.environment}.tfstate"
    use_azuread_auth     = true
  }
}

locals {
  apim_name                = data.terraform_remote_state.platform.outputs.apim_name
  apim_resource_group_name = data.terraform_remote_state.platform.outputs.apim_resource_group_name
}
```

Remote state was chosen over `data "azurerm_api_management"` because this
repository owns the platform, so the outputs are a versioned contract that
also carries things a data source cannot (product ids, logger id, the naming
suffix, the agent client). If the platform moved to another repository, the
same locals would switch to data sources without touching the modules.

## Data-driven registration

`terraform/api-onboarding/<env>/locals.tf`:

```hcl
api_dirs   = toset([for f in fileset("${path.module}/../../../apis", "*/api.yaml") : dirname(f)])
discovered = { for d in api_dirs : d => yamldecode(file(".../apis/${d}/api.yaml")) }
selected   = var.enabled_apis == null ? discovered : { for d, c in discovered : d => c if contains(var.enabled_apis, d) }
```

then `module "api" { for_each = local.apis ... }`. YAML is parsed by Terraform
itself (`yamldecode`), which is why there is no preprocessing step: the cost
is that a malformed file would fail inside Terraform with a poor message, so
`scripts/onboarding-check.sh` validates every file against
`schemas/api.schema.json` first in CI.

## Adopting the resource group

Bootstrap creates `rg-cloudapiworkflow` so RBAC can be scoped to it before the
platform identity exists. The platform layer then owns it through a
config-driven `import` block in `terraform/platform/<env>/main.tf`:

```hcl
import {
  to = azurerm_resource_group.main
  id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
}
```

The first plan shows `1 to import`; afterwards the block is a no-op, so it
stays in the code as documentation of where the group came from.

## First-time setup (platform administrator)

```bash
# 1. bootstrap (local state, then migrate)
cd terraform/bootstrap
cat > backend_override.tf <<'EOF'
terraform { backend "local" {} }
EOF
terraform init && terraform apply
rm backend_override.tf
terraform init -migrate-state \
  -backend-config=resource_group_name=rg-cloudapiworkflow-state \
  -backend-config=storage_account_name=stcawstate4k7m \
  -backend-config=container_name=bootstrap \
  -backend-config=key=bootstrap.tfstate \
  -backend-config=use_azuread_auth=true

# 2. GitHub: variables + environments (see docs/branch-protection.md)
# 3. run the platform-deploy workflow (workflow_dispatch) -> creates APIM once
# 4. every later API lands through api-ci / api-deploy
```

## Versions

* Terraform `1.16.2` (`.terraform-version`, pinned in CI); `required_version = ">= 1.16.0, < 2.0.0"`
* `hashicorp/azurerm ~> 4.0`, `hashicorp/azuread ~> 3.0`, `hashicorp/random ~> 3.6`, `hashicorp/time ~> 0.12`
* Lock files (`.terraform.lock.hcl`) are committed per root; CI runs `init -lockfile=readonly`

## Upgrading APIM without touching APIs

Because the API layer only references the instance by name, a SKU change
(`apim_sku_name`, `apim_vnet_integration`) is a platform PR that updates the
instance in place. The onboarding state is unaffected. A change that would
*replace* the instance is blocked by `prevent_destroy` on the module and must
be an explicit, planned migration.
