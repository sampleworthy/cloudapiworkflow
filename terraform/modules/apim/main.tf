# Shared Azure API Management instance - the SERVICE only.
#
# Terraform owns the ARM resource (SKU, identity, network, TLS posture) and
# its resource-log wiring. Everything inside the instance (APIs, products,
# policies, named values, loggers, diagnostics, version sets, backends) is
# owned by Microsoft APIOps from apim/artifacts and is never declared here.
# A plan that shows -/+ on this resource is a platform migration, not a
# routine change; prevent_destroy makes it an explicit decision.

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
    prevent_destroy = true
  }
}

# Resource logs to Log Analytics. Not available on the Consumption tier.
resource "azurerm_monitor_diagnostic_setting" "gateway" {
  count = local.is_consumption ? 0 : 1

  name                       = "diag-gateway-logs"
  target_resource_id         = azurerm_api_management.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "GatewayLogs"
  }
}
