# Reusable "one API in the shared APIM instance" module.
#
# Everything an API team needs is expressed as inputs; the module owns the
# APIM resources for exactly one API version. It never creates or reads the
# APIM service itself: apim_name / resource_group_name come from the caller
# (platform remote state), so this module can be instantiated N times with
# for_each without any effect on the gateway.

locals {
  # Policy XML lives in Git next to the OpenAPI document. templatefile() lets
  # the same XML carry environment-specific values (audience, tenant, limits)
  # without the team hard-coding them.
  policy_xml = templatefile(var.policy_file, merge({
    audience          = var.auth.audience
    audiences         = var.auth.audiences
    required_roles    = var.auth.required_roles
    write_roles       = var.auth.write_roles
    backend_id        = var.api_name
    backend_url       = var.backend_url
    backend_audience  = var.backend_auth.audience
    rate_limit_calls  = var.rate_limit.calls
    rate_limit_period = var.rate_limit.renewal_period
    mock_responses    = var.mock_responses
  }, var.policy_vars))

  openapi_content = file(var.openapi_file)
}

resource "azurerm_api_management_api" "this" {
  name                = var.api_name
  resource_group_name = var.resource_group_name
  api_management_name = var.apim_name
  revision            = tostring(var.revision)
  display_name        = var.display_name
  description         = var.description
  path                = var.path
  protocols           = ["https"]
  service_url         = var.backend_url

  subscription_required = var.subscription_required
  version               = var.version_set_id == null ? null : var.api_version
  version_set_id        = var.version_set_id

  import {
    content_format = endswith(var.openapi_file, ".json") ? "openapi+json" : "openapi"
    content_value  = local.openapi_content
  }

  subscription_key_parameter_names {
    header = "Ocp-Apim-Subscription-Key"
    query  = "subscription-key"
  }
}

# Backend entity: keeps the backend URL and TLS settings in one place so the
# policy can use set-backend-service backend-id="..." instead of a raw URL.
resource "azurerm_api_management_backend" "this" {
  name                = var.api_name
  resource_group_name = var.resource_group_name
  api_management_name = var.apim_name
  protocol            = "http"
  url                 = var.backend_url
  description         = "Backend for ${var.display_name}"

  tls {
    validate_certificate_chain = true
    validate_certificate_name  = true
  }
}

resource "azurerm_api_management_api_policy" "this" {
  api_name            = azurerm_api_management_api.this.name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  xml_content         = local.policy_xml

  depends_on = [azurerm_api_management_backend.this]
}

resource "azurerm_api_management_product_api" "this" {
  for_each = toset(var.product_ids)

  api_name            = azurerm_api_management_api.this.name
  product_id          = each.value
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_api_management_api_diagnostic" "this" {
  count = var.enable_diagnostics && var.logger_id != null ? 1 : 0

  identifier               = "applicationinsights"
  resource_group_name      = var.resource_group_name
  api_management_name      = var.apim_name
  api_name                 = azurerm_api_management_api.this.name
  api_management_logger_id = var.logger_id

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
