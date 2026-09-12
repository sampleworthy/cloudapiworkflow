# Microsoft Foundry: one Foundry resource (Cognitive Services account, kind
# AIServices, project management enabled), one project, one model deployment,
# and a project connection to the shared Application Insights for agent
# tracing. Agents themselves are NOT created here: they have their own
# lifecycle (agents/ + agent-deploy). Terraform provides the runtime, the
# identities and the RBAC.

resource "azurerm_cognitive_account" "this" {
  name                  = var.name
  location              = var.location
  resource_group_name   = var.resource_group_name
  kind                  = "AIServices"
  sku_name              = "S0"
  custom_subdomain_name = var.name

  # Foundry projects and the Agent Service require project management.
  project_management_enabled = true

  # Entra only: no API keys anywhere in the platform.
  local_auth_enabled            = false
  public_network_access_enabled = var.public_network_access_enabled

  identity {
    type = "SystemAssigned"
  }

  dynamic "network_acls" {
    for_each = var.public_network_access_enabled ? [] : [1]
    content {
      default_action = "Deny"
      bypass         = "AzureServices"
    }
  }

  tags = var.tags
}

resource "azurerm_cognitive_account_project" "this" {
  name                 = var.project_name
  cognitive_account_id = azurerm_cognitive_account.this.id
  location             = var.location
  display_name         = var.project_display_name
  description          = var.project_description

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# One model is enough for the demo; multi-model routing is an APIM backend
# pool concern documented in docs/ai-gateway.md.
resource "azurerm_cognitive_deployment" "model" {
  name                 = var.model.deployment_name
  cognitive_account_id = azurerm_cognitive_account.this.id

  model {
    format  = "OpenAI"
    name    = var.model.name
    version = var.model.version
  }

  sku {
    name     = var.model.sku
    capacity = var.model.capacity
  }

  version_upgrade_option = "OnceNewDefaultVersionAvailable"
}

# Agent tracing -> the platform's Application Insights. The project-level
# connection is not yet in azurerm, so it is declared through azapi.
resource "azapi_resource" "appinsights_connection" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = "appinsights"
  parent_id = azurerm_cognitive_account_project.this.id

  body = {
    properties = {
      category      = "AppInsights"
      target        = var.app_insights_id
      authType      = "ApiKey"
      isSharedToAll = true
      credentials = {
        key = var.app_insights_connection_string
      }
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.app_insights_id
      }
    }
  }

  schema_validation_enabled = false
  ignore_missing_property   = true
}

# Diagnostics for the Foundry resource (model requests, agent runs) to the
# shared workspace.
resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_cognitive_account.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}

# Optional private endpoint (prod): resolves the account, OpenAI and Foundry
# API hostnames through the three privatelink zones the networking module owns.
resource "azurerm_private_endpoint" "this" {
  count = var.private_endpoint_subnet_id == null ? 0 : 1

  name                = "pe-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = azurerm_cognitive_account.this.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.private_dns_zone_ids) == 0 ? [] : [1]
    content {
      name                 = "default"
      private_dns_zone_ids = var.private_dns_zone_ids
    }
  }
}
