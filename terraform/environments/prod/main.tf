# ===========================================================================
# PLATFORM ENVIRONMENT ROOT
#
# Terraform owns the Azure platform: resource group, network, monitoring,
# Key Vault, the APIM service, backend hosting, and the Entra objects used
# at runtime and by the demo. It does NOT own anything inside APIM: APIs,
# products, policies, named values, loggers and diagnostics are published by
# Microsoft APIOps from apim/artifacts.
#
# terraform/environments/dev and /prod are byte-identical apart from
# terraform.tfvars and backend.tf; CI enforces it.
# ===========================================================================

data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

locals {
  name_prefix        = var.name_prefix
  github_environment = var.environment == "prod" ? "production" : "development"
  tenant_id          = data.azurerm_client_config.current.tenant_id

  tags = merge(var.tags, {
    environment = var.environment
    layer       = "platform"
    managedBy   = "terraform"
    repository  = var.github_repository
  })
}

# Suffix for globally unique names (APIM, Key Vault, web apps).
resource "random_string" "suffix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# ---------------------------------------------------------------------------
# Resource group: created empty by bootstrap (so RBAC could be scoped to it
# before this identity existed), adopted here. The import block is a no-op
# once the group is in state.
# ---------------------------------------------------------------------------

import {
  to = azurerm_resource_group.main
  id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Network, monitoring, Key Vault
# ---------------------------------------------------------------------------

module "networking" {
  source = "../../modules/networking"

  name                        = "vnet-${local.name_prefix}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  apim_subnet_delegate_to_web = true
  tags                        = local.tags
}

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

module "key_vault" {
  source = "../../modules/key-vault"

  name                          = "kv-${local.name_prefix}-${random_string.suffix.result}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  tenant_id                     = local.tenant_id
  purge_protection_enabled      = var.key_vault_purge_protection
  public_network_access_enabled = !var.enable_private_endpoints
  private_endpoint_subnet_id    = var.enable_private_endpoints ? module.networking.private_endpoint_subnet_id : null
  private_dns_zone_id           = var.enable_private_endpoints ? module.networking.private_dns_zone_ids["privatelink.vaultcore.azure.net"] : null
  secrets_officer_principal_ids = [data.azurerm_client_config.current.object_id]
  tags                          = local.tags
}

resource "time_sleep" "key_vault_rbac" {
  create_duration = "90s"
  triggers = {
    assignments = join(",", module.key_vault.secrets_officer_role_assignment_ids)
  }
}

# ---------------------------------------------------------------------------
# APIM service (the shared gateway). Created once; APIOps fills it.
# ---------------------------------------------------------------------------

module "apim" {
  source = "../../modules/apim"

  name                          = "apim-${local.name_prefix}-${random_string.suffix.result}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  publisher_name                = var.apim_publisher_name
  publisher_email               = var.apim_publisher_email
  sku_name                      = var.apim_sku_name
  vnet_subnet_id                = var.apim_vnet_integration ? module.networking.apim_subnet_id : null
  public_network_access_enabled = true
  log_analytics_workspace_id    = module.monitoring.log_analytics_workspace_id
  tags                          = local.tags
}

data "azuread_service_principal" "apim_identity" {
  object_id = module.apim.identity_principal_id
}

# APIOps configures the App Insights logger through a Key Vault-backed named
# value, so the connection string never appears in Git: Terraform puts it in
# the vault and lets the gateway identity read it.
resource "azurerm_key_vault_secret" "appinsights_connection_string" {
  name         = "appinsights-connection-string"
  value        = module.monitoring.app_insights_connection_string
  key_vault_id = module.key_vault.id
  content_type = "application-insights-connection-string"
  tags         = local.tags

  depends_on = [time_sleep.key_vault_rbac]
}

resource "azurerm_role_assignment" "apim_key_vault_secrets_user" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.apim.identity_principal_id
}

# ---------------------------------------------------------------------------
# Entra ID: one resource application per environment exposing every API's
# application permissions as app roles. APIM validates audience + roles;
# backends validate the same registration through Easy Auth.
# ---------------------------------------------------------------------------

module "api_resource_app" {
  source = "../../modules/identity"

  name         = "${local.name_prefix}-${var.environment}"
  display_name = "Cloud API Workflow APIs (${var.environment})"
  description  = "Resource application for every API published through the shared gateway in ${var.environment}. App roles are the API permissions."
  tenant_id    = local.tenant_id
  app_roles    = var.api_app_roles
  owners       = [data.azuread_client_config.current.object_id]
  tags         = ["cloudapiworkflow", var.environment, "api-resource"]

  client_grants = {
    for k, c in var.demo_clients : k => {
      principal_object_id = azuread_service_principal.demo_client[k].object_id
      roles               = c.roles
    } if length(c.roles) > 0
  }
}

# Demo machine-to-machine clients. "agent" holds real roles; "unprivileged"
# holds none, which is what makes the 403 test genuine. Both authenticate
# with GitHub federated credentials in CI; a client secret exists only in
# Key Vault for scripts/get-token.sh.
resource "azuread_application" "demo_client" {
  for_each = var.demo_clients

  display_name = "${local.name_prefix}-${each.key}-client-${var.environment}"
  description  = each.value.description
  owners       = [data.azuread_client_config.current.object_id]
  tags         = ["cloudapiworkflow", var.environment, "demo-client", each.key]
}

resource "azuread_service_principal" "demo_client" {
  for_each = var.demo_clients

  client_id = azuread_application.demo_client[each.key].client_id
  owners    = [data.azuread_client_config.current.object_id]
  tags      = ["cloudapiworkflow", var.environment, "demo-client", each.key]
}

resource "azuread_application_federated_identity_credential" "demo_client_github" {
  for_each = var.demo_clients

  application_id = azuread_application.demo_client[each.key].id
  display_name   = "github-${local.github_environment}"
  description    = "Lets the ${local.github_environment} deployment jobs acquire API tokens for post-deployment tests without a secret."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:environment:${local.github_environment}"
}

resource "time_rotating" "demo_client_secret" {
  rotation_days = 90
}

resource "azuread_application_password" "demo_client" {
  for_each = var.demo_clients

  application_id = azuread_application.demo_client[each.key].id
  display_name   = "local-testing"
  end_date       = timeadd(time_rotating.demo_client_secret.rotation_rfc3339, "168h")

  rotate_when_changed = {
    rotation = time_rotating.demo_client_secret.id
  }
}

resource "azurerm_key_vault_secret" "demo_client_secret" {
  for_each = var.demo_clients

  name         = "${each.key}-client-secret"
  value        = azuread_application_password.demo_client[each.key].value
  key_vault_id = module.key_vault.id
  content_type = "entra-client-secret"
  tags         = local.tags

  depends_on = [time_sleep.key_vault_rbac]
}

# ---------------------------------------------------------------------------
# Backend hosting for the demo APIs: one shared plan, one web app per API,
# each locked to the gateway's managed identity. These are workloads the API
# teams "already run"; onboarding them to the gateway is an APIOps change.
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "backends" {
  name                = "asp-${local.name_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
  tags                = local.tags
}

module "backend_app" {
  for_each = toset(var.backend_apps)
  source   = "../../modules/app-service"

  name                = "app-${each.key}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.backends.id

  vnet_integration_subnet_id    = module.networking.app_integration_subnet_id
  public_network_access_enabled = !var.enable_private_endpoints
  private_endpoint_subnet_id    = var.enable_private_endpoints ? module.networking.private_endpoint_subnet_id : null
  private_dns_zone_id           = var.enable_private_endpoints ? module.networking.private_dns_zone_ids["privatelink.azurewebsites.net"] : null
  allowed_ip_addresses          = try(coalesce(module.apim.public_ip_addresses, []), [])

  auth_client_id          = module.api_resource_app.client_id
  auth_tenant_endpoint    = "https://sts.windows.net/${local.tenant_id}/"
  auth_allowed_client_ids = [data.azuread_service_principal.apim_identity.client_id]
  auth_allowed_audiences  = [module.api_resource_app.identifier_uri, module.api_resource_app.client_id]

  app_insights_connection_string = module.monitoring.app_insights_connection_string
  log_analytics_workspace_id     = module.monitoring.log_analytics_workspace_id

  app_settings = {
    API_NAME    = each.key
    ENVIRONMENT = var.environment
  }

  tags = merge(local.tags, { api = each.key })
}

# Backend -> Key Vault with managed identity (no secrets in app settings).
resource "azurerm_role_assignment" "backend_key_vault_secrets_user" {
  for_each = module.backend_app

  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value.identity_principal_id
}
