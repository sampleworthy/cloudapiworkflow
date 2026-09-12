# ===========================================================================
# PLATFORM LAYER - shared, long-lived infrastructure
#
# Owns: resource group, VNet, Log Analytics, App Insights, Key Vault, the
# shared APIM instance (products, global policy, logger), the shared App
# Service Plan and the demo agent client identity.
#
# This root changes rarely. API onboarding never touches it: the
# api-onboarding layer consumes this layer's outputs through remote state.
#
# terraform/platform/dev and terraform/platform/prod are byte-identical apart
# from terraform.tfvars and backend.tf; CI enforces that (see
# .github/workflows/terraform-platform-ci.yml "roots-in-sync").
# ===========================================================================

data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

locals {
  name_prefix        = var.name_prefix
  github_environment = var.environment == "prod" ? "production" : "development"

  tags = merge(var.tags, {
    environment = var.environment
    layer       = "platform"
    managedBy   = "terraform"
    repository  = var.github_repository
  })
}

# Suffix for globally unique names (APIM, Key Vault, web apps). Stored in
# state, so it is stable for the life of the environment.
resource "random_string" "suffix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# ---------------------------------------------------------------------------
# Resource group. Created empty by bootstrap (so RBAC could be scoped to it),
# adopted here on the first run via `terraform import` in the deploy workflow.
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Shared networking
# ---------------------------------------------------------------------------

module "networking" {
  source = "../../modules/networking"

  name                        = "vnet-${local.name_prefix}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  apim_subnet_delegate_to_web = true # StandardV2 outbound integration (prod)
  tags                        = local.tags
}

# ---------------------------------------------------------------------------
# Shared monitoring
# ---------------------------------------------------------------------------

module "monitoring" {
  source = "../../modules/monitoring"

  log_analytics_name  = "log-${local.name_prefix}"
  app_insights_name   = "appi-${local.name_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Key Vault
# ---------------------------------------------------------------------------

module "key_vault" {
  source = "../../modules/key-vault"

  name                          = "kv-${local.name_prefix}-${random_string.suffix.result}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  purge_protection_enabled      = var.key_vault_purge_protection
  public_network_access_enabled = !var.enable_private_endpoints
  private_endpoint_subnet_id    = var.enable_private_endpoints ? module.networking.private_endpoint_subnet_id : null
  private_dns_zone_id           = var.enable_private_endpoints ? module.networking.private_dns_zone_ids["privatelink.vaultcore.azure.net"] : null

  # Whoever applies this layer (the platform deployer in CI) writes secrets.
  secrets_officer_principal_ids = [data.azurerm_client_config.current.object_id]
  tags                          = local.tags
}

# RBAC propagation takes up to a couple of minutes; wait before first write.
resource "time_sleep" "key_vault_rbac" {
  create_duration = "90s"
  triggers = {
    assignments = join(",", module.key_vault.secrets_officer_role_assignment_ids)
  }
}

# ---------------------------------------------------------------------------
# Shared APIM instance
# ---------------------------------------------------------------------------

module "apim" {
  source = "../../modules/apim"

  name                = "apim-${local.name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = var.apim_sku_name

  vnet_subnet_id                = var.apim_vnet_integration ? module.networking.apim_subnet_id : null
  public_network_access_enabled = true

  named_values = {
    "tenant-id"   = { value = data.azurerm_client_config.current.tenant_id }
    "environment" = { value = var.environment }
  }

  global_policy_xml = file("${path.module}/../policies/global.xml")

  products = {
    internal-apis = {
      display_name          = "Internal APIs"
      description           = "First-party APIs for internal services. Entra token required; no subscription key."
      subscription_required = false
      policy_xml            = file("${path.module}/../policies/products/internal-apis.xml")
    }
    partner-apis = {
      display_name          = "Partner APIs"
      description           = "APIs exposed to external partners. Subscription key and Entra token required."
      subscription_required = true
      approval_required     = true
      subscriptions_limit   = 5
      policy_xml            = file("${path.module}/../policies/products/partner-apis.xml")
    }
    agent-apis = {
      display_name          = "Agent APIs"
      description           = "APIs consumed by AI agents and automation via client credentials."
      subscription_required = false
      policy_xml            = file("${path.module}/../policies/products/agent-apis.xml")
    }
  }

  app_insights_id                = module.monitoring.app_insights_id
  app_insights_connection_string = module.monitoring.app_insights_connection_string
  log_analytics_workspace_id     = module.monitoring.log_analytics_workspace_id
  diagnostic_sampling_percentage = var.apim_diagnostic_sampling_percentage
  tags                           = local.tags
}

# The managed identity's *client id* is what App Service Easy Auth allow-lists.
data "azuread_service_principal" "apim_identity" {
  object_id = module.apim.identity_principal_id
}

# ---------------------------------------------------------------------------
# Shared App Service Plan for backend APIs. One plan, many apps: the
# onboarding layer creates a web app per API on it.
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "backends" {
  name                = "asp-${local.name_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
  tags                = local.tags
}

# The API deployer must be able to join web apps to the integration subnet.
# Granted here (scoped to the one subnet) rather than at bootstrap because
# the subnet does not exist until this layer runs.
data "azuread_service_principal" "api_deployer" {
  display_name = var.api_deployer_display_name
}

resource "azurerm_role_assignment" "api_deployer_subnet_join" {
  scope                = module.networking.app_integration_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = data.azuread_service_principal.api_deployer.object_id
}

# ---------------------------------------------------------------------------
# Demo machine-to-machine client ("AI agent"). One shared client is granted
# roles on each API by the onboarding layer. It authenticates to Entra with:
#   * a GitHub federated credential (CI smoke tests, no secret), and
#   * a client secret kept ONLY in Key Vault for local scripts/get-token.sh.
# ---------------------------------------------------------------------------

resource "azuread_application" "agent_client" {
  display_name = "${local.name_prefix}-agent-client-${var.environment}"
  description  = "Demo M2M caller for ${var.environment}. Acquires client-credentials tokens for onboarded APIs."
  owners       = [data.azuread_client_config.current.object_id]
  tags         = ["cloudapiworkflow", var.environment, "agent-client"]
}

resource "azuread_service_principal" "agent_client" {
  client_id = azuread_application.agent_client.client_id
  owners    = [data.azuread_client_config.current.object_id]
  tags      = ["cloudapiworkflow", var.environment, "agent-client"]
}

resource "azuread_application_federated_identity_credential" "agent_client_github" {
  application_id = azuread_application.agent_client.id
  display_name   = "github-${local.github_environment}"
  description    = "Lets the ${local.github_environment} deployment job acquire API tokens for smoke tests without a secret."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:environment:${local.github_environment}"
}

resource "time_rotating" "agent_client_secret" {
  rotation_days = 90
}

resource "azuread_application_password" "agent_client" {
  application_id = azuread_application.agent_client.id
  display_name   = "local-testing"
  end_date       = timeadd(time_rotating.agent_client_secret.rotation_rfc3339, "168h")

  rotate_when_changed = {
    rotation = time_rotating.agent_client_secret.id
  }
}

resource "azurerm_key_vault_secret" "agent_client_secret" {
  name         = "agent-client-secret"
  value        = azuread_application_password.agent_client.value
  key_vault_id = module.key_vault.id
  content_type = "entra-client-secret"
  tags         = local.tags

  depends_on = [time_sleep.key_vault_rbac]
}
