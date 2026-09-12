# ===========================================================================
# API ONBOARDING LAYER
#
# Adds APIs to the EXISTING shared APIM instance. This root never contains an
# azurerm_api_management resource; it reads the instance from platform remote
# state (locals.tf) and instantiates the apim-api module once per api.yaml.
#
# Per API this layer owns:
#   * version set (one per unique versionSet)             azurerm_api_management_api_version_set
#   * Entra resource app + app roles + client grants       modules/identity
#   * backend web app on the shared plan (if requested)   modules/app-service
#   * API, policy, backend entity, product link, diagnostic   modules/apim-api
#
# terraform/api-onboarding/dev and /prod are byte-identical apart from
# terraform.tfvars and backend.tf; CI enforces it.
# ===========================================================================

data "azuread_client_config" "current" {}

locals {
  tags = merge(var.tags, {
    environment = var.environment
    layer       = "api-onboarding"
    managedBy   = "terraform"
  })
}

# ---------------------------------------------------------------------------
# Version sets: /<path>/v1, /<path>/v2 ... under one logical API.
# ---------------------------------------------------------------------------

resource "azurerm_api_management_api_version_set" "this" {
  for_each = toset(local.version_sets)

  name                = each.key
  resource_group_name = local.apim_resource_group_name
  api_management_name = local.apim_name
  display_name        = each.key
  versioning_scheme   = "Segment"
  description         = "Version set for ${each.key}; managed by terraform/api-onboarding."
}

# ---------------------------------------------------------------------------
# Identity: one Entra resource app per API, with the roles declared in
# api.yaml. Allowed shared clients are granted every role of the API.
# ---------------------------------------------------------------------------

module "identity" {
  for_each = local.apis_with_entra
  source   = "../../modules/identity"

  name         = "${each.value.name}-${var.environment}"
  display_name = "${each.value.display_name} (${var.environment})"
  description  = "Resource application for ${each.value.display_name}. Managed by terraform/api-onboarding from apis/${each.key}/api.yaml."
  tenant_id    = local.platform.tenant_id
  app_roles    = each.value.auth.roles
  owners       = [data.azuread_client_config.current.object_id]
  tags         = ["cloudapiworkflow", var.environment, "api-resource", each.value.name]

  client_grants = {
    for c in each.value.auth.allowed_clients : c => {
      principal_object_id = local.clients[c]
      roles               = keys(each.value.auth.roles)
    }
  }
}

# ---------------------------------------------------------------------------
# Backend compute for APIs that ask for it (backend.type: app_service).
# Locked to the APIM managed identity via Easy Auth.
# ---------------------------------------------------------------------------

module "backend_app" {
  for_each = local.apis_with_web_app
  source   = "../../modules/app-service"

  name                = "app-${each.value.name}-${local.platform.resource_suffix}"
  location            = local.platform.location
  resource_group_name = local.apim_resource_group_name
  service_plan_id     = local.platform.app_service_plan_id

  vnet_integration_subnet_id    = local.platform.app_integration_subnet_id
  public_network_access_enabled = !local.platform.enable_private_endpoints
  private_endpoint_subnet_id    = local.platform.enable_private_endpoints ? local.platform.private_endpoint_subnet_id : null
  private_dns_zone_id           = local.platform.enable_private_endpoints ? local.platform.private_dns_zone_ids["privatelink.azurewebsites.net"] : null
  allowed_ip_addresses          = try(coalesce(local.platform.apim_public_ip_addresses, []), [])

  auth_client_id          = module.identity[each.key].client_id
  auth_tenant_endpoint    = "https://sts.windows.net/${local.platform.tenant_id}/"
  auth_allowed_client_ids = [local.platform.apim_identity_client_id]
  auth_allowed_audiences  = [module.identity[each.key].identifier_uri, module.identity[each.key].client_id]

  app_insights_connection_string = local.platform.app_insights_connection_string
  log_analytics_workspace_id     = local.platform.log_analytics_workspace_id

  app_settings = {
    API_NAME    = each.value.name
    API_VERSION = each.value.version
    ENVIRONMENT = var.environment
  }

  tags = merge(local.tags, { api = each.value.name, owner = coalesce(each.value.owner, "unassigned") })
}

# ---------------------------------------------------------------------------
# The API itself, inside the existing gateway.
# ---------------------------------------------------------------------------

module "api" {
  for_each = local.apis
  source   = "../../modules/apim-api"

  # where (from platform remote state)
  apim_name           = local.apim_name
  resource_group_name = local.apim_resource_group_name
  logger_id           = local.platform.apim_logger_id

  # what (from apis/<dir>/api.yaml)
  api_name       = "${each.value.name}-${each.value.version}"
  display_name   = each.value.display_name
  description    = each.value.description
  path           = each.value.path
  api_version    = each.value.version
  version_set_id = azurerm_api_management_api_version_set.this[each.value.version_set].id
  revision       = each.value.revision
  openapi_file   = each.value.openapi_file
  policy_file    = each.value.policy_file

  backend_url    = local.backend_urls[each.key]
  mock_responses = each.value.backend.type == "mock"
  backend_auth = {
    type     = each.value.backend.type == "app_service" ? "managed_identity" : "none"
    audience = each.value.backend.type == "app_service" ? module.identity[each.key].identifier_uri : ""
  }

  product_ids           = [local.platform.product_ids[each.value.product]]
  subscription_required = each.value.subscription_required

  auth = {
    audience       = module.identity[each.key].identifier_uri
    audiences      = [module.identity[each.key].identifier_uri, module.identity[each.key].client_id]
    required_roles = each.value.auth.required_roles
    write_roles    = each.value.auth.write_roles
  }

  rate_limit                     = each.value.rate_limit
  enable_diagnostics             = each.value.diagnostics.enabled
  diagnostic_sampling_percentage = each.value.diagnostics.sampling_percentage
  tags                           = local.tags
}
