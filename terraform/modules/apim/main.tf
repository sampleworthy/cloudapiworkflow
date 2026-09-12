# Shared Azure API Management instance.
#
# This module is applied by the PLATFORM layer only. API teams never touch it:
# onboarding an API adds resources *inside* this instance through the apim-api
# module in the api-onboarding layer, which references this instance by name
# via remote state. If a plan ever shows -/+ on azurerm_api_management.this,
# that is a platform change and must go through the platform workflow.

locals {
  is_consumption = startswith(var.sku_name, "Consumption")
  is_v2          = endswith(split("_", var.sku_name)[0], "V2")

  # Consumption has no VNet support; classic tiers use injection; V2 tiers use
  # outbound integration. All three are expressed through the same variable.
  vnet_type = var.vnet_subnet_id == null || local.is_consumption ? "None" : (local.is_v2 ? "External" : var.classic_vnet_type)
}

resource "azurerm_api_management" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.sku_name

  identity {
    type = "SystemAssigned"
  }

  virtual_network_type          = local.vnet_type
  public_network_access_enabled = var.public_network_access_enabled

  dynamic "virtual_network_configuration" {
    for_each = local.vnet_type == "None" ? [] : [1]
    content {
      subnet_id = var.vnet_subnet_id
    }
  }

  # Platform-wide hardening: no legacy TLS/ciphers on the gateway.
  security {
    backend_ssl30_enabled  = false
    backend_tls10_enabled  = false
    backend_tls11_enabled  = false
    frontend_ssl30_enabled = false
    frontend_tls10_enabled = false
    frontend_tls11_enabled = false
  }

  tags = var.tags

  lifecycle {
    # Onboarding APIs must never be able to replace the gateway. Any change
    # that would force replacement fails the plan instead.
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Named values consumed by policies ({{tenant-id}} etc.). Policies in Git
# reference these by name so no tenant identifiers live in the XML.
# ---------------------------------------------------------------------------

resource "azurerm_api_management_named_value" "this" {
  for_each = var.named_values

  name                = each.key
  display_name        = each.key
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  value               = each.value.value
  secret              = each.value.secret
}

# ---------------------------------------------------------------------------
# Global policy: correlation id, security headers, standard error shape.
# ---------------------------------------------------------------------------

resource "azurerm_api_management_policy" "global" {
  api_management_id = azurerm_api_management.this.id
  xml_content       = var.global_policy_xml

  depends_on = [azurerm_api_management_named_value.this]
}

# ---------------------------------------------------------------------------
# Products. APIs are attached to these by the onboarding layer; the products
# themselves are shared and never recreated per API.
# ---------------------------------------------------------------------------

resource "azurerm_api_management_product" "this" {
  for_each = var.products

  product_id            = each.key
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = var.resource_group_name
  display_name          = each.value.display_name
  description           = each.value.description
  subscription_required = each.value.subscription_required
  approval_required     = each.value.subscription_required ? each.value.approval_required : null
  subscriptions_limit   = each.value.subscription_required ? each.value.subscriptions_limit : null
  published             = true
}

resource "azurerm_api_management_product_policy" "this" {
  for_each = { for k, p in var.products : k => p if p.policy_xml != null }

  product_id          = azurerm_api_management_product.this[each.key].product_id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  xml_content         = each.value.policy_xml

  depends_on = [azurerm_api_management_named_value.this]
}

# ---------------------------------------------------------------------------
# Observability: Application Insights logger + gateway-wide diagnostics.
# Per-API diagnostics are added by the apim-api module and reuse this logger.
# ---------------------------------------------------------------------------

resource "azurerm_api_management_logger" "app_insights" {
  name                = "appinsights"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  resource_id         = var.app_insights_id
  description         = "Shared Application Insights logger for all APIs"

  application_insights {
    connection_string = var.app_insights_connection_string
  }
}

resource "azurerm_api_management_diagnostic" "app_insights" {
  identifier               = "applicationinsights"
  resource_group_name      = var.resource_group_name
  api_management_name      = azurerm_api_management.this.name
  api_management_logger_id = azurerm_api_management_logger.app_insights.id

  sampling_percentage       = var.diagnostic_sampling_percentage
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"
  http_correlation_protocol = "W3C"

  frontend_request {
    body_bytes     = 0
    headers_to_log = ["X-Correlation-Id", "User-Agent"]
  }

  frontend_response {
    body_bytes     = 0
    headers_to_log = ["X-Correlation-Id", "Retry-After"]
  }

  backend_request {
    body_bytes     = 0
    headers_to_log = ["X-Correlation-Id"]
  }

  backend_response {
    body_bytes     = 0
    headers_to_log = ["X-Correlation-Id"]
  }
}

# Resource logs to Log Analytics. Not available on the Consumption tier, so
# the setting is created only when the tier supports it.
resource "azurerm_monitor_diagnostic_setting" "gateway" {
  count = local.is_consumption ? 0 : 1

  name                       = "diag-gateway-logs"
  target_resource_id         = azurerm_api_management.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "GatewayLogs"
  }

  enabled_log {
    category = "WebSocketConnectionLogs"
  }
}
