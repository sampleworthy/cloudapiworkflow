# Backend web app for one API, hosted on the shared App Service Plan.
#
# "Consumers cannot bypass APIM" is enforced by identity, which works on every
# APIM tier including Consumption:
#   * built-in authentication (Easy Auth) rejects any request that does not
#     carry a token issued for this app's own registration, AND
#   * only the APIM managed identity is an allowed client application.
# APIM obtains that token with <authentication-managed-identity>. A consumer
# who discovers the *.azurewebsites.net hostname gets 401 from the platform
# before any application code runs.
#
# In prod tfvars, public_network_access_enabled=false plus a private endpoint
# closes the network path as well.

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = var.service_plan_id
  https_only          = true

  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.vnet_integration_subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on              = var.always_on
    ftps_state             = "Disabled"
    minimum_tls_version    = "1.2"
    http2_enabled          = true
    vnet_route_all_enabled = var.vnet_integration_subnet_id != null
    app_command_line       = var.startup_command
    health_check_path      = var.health_check_path
    # Provider-managed equivalent of WEBSITE_HEALTHCHECK_MAXPINGFAILURES
    health_check_eviction_time_in_min = 2

    application_stack {
      python_version = var.python_version
    }

    # Network-layer allow list. On tiers where APIM has static egress IPs the
    # platform passes them in; with an empty list nothing is added and Easy
    # Auth remains the control.
    dynamic "ip_restriction" {
      for_each = var.allowed_ip_addresses
      content {
        name       = "allow-apim-${ip_restriction.key}"
        action     = "Allow"
        priority   = 100 + ip_restriction.key
        ip_address = "${ip_restriction.value}/32"
      }
    }

    dynamic "ip_restriction" {
      for_each = length(var.allowed_ip_addresses) > 0 ? [1] : []
      content {
        name       = "deny-all"
        action     = "Deny"
        priority   = 2147483647
        ip_address = "0.0.0.0/0"
      }
    }
  }

  auth_settings_v2 {
    auth_enabled           = true
    require_authentication = true
    unauthenticated_action = "Return401"
    default_provider       = "azureactivedirectory"
    require_https          = true

    active_directory_v2 {
      client_id            = var.auth_client_id
      tenant_auth_endpoint = var.auth_tenant_endpoint
      allowed_applications = var.auth_allowed_client_ids
      allowed_audiences    = var.auth_allowed_audiences
    }

    login {
      token_store_enabled = false
    }
  }

  app_settings = merge(
    {
      # Packages are built on the CI runner and deployed prebuilt (no Oryx build on the
      # shared B1 plan); the dependencies live under .python_packages inside the zip.
      "SCM_DO_BUILD_DURING_DEPLOYMENT"        = "false"
      "PYTHONPATH"                            = "/home/site/wwwroot/.python_packages/lib/site-packages"
      "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.app_insights_connection_string
      # The Linux Python auto-instrumentation agent (ApplicationInsightsAgent_EXTENSION_VERSION=~3)
      # injects /agents/python/common with an old typing_extensions that shadows the app's
      # dependencies (FastAPI fails to import). Telemetry comes from APIM diagnostics, App
      # Service logs and, if wanted, the OpenTelemetry SDK inside the app instead.
    },
    var.app_settings
  )

  tags = var.tags

  lifecycle {
    # Application code is deployed by its own pipeline; do not fight it.
    ignore_changes = [
      site_config[0].application_stack,
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  enabled_log {
    category = "AppServiceAppLogs"
  }

  enabled_log {
    category = "AppServiceAuthenticationLogs"
  }
}

# Optional private endpoint (prod).
resource "azurerm_private_endpoint" "this" {
  count = var.enable_private_endpoint ? 1 : 0

  name                = "pe-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = azurerm_linux_web_app.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_id == null ? [] : [1]
    content {
      name                 = "default"
      private_dns_zone_ids = [var.private_dns_zone_id]
    }
  }
}
