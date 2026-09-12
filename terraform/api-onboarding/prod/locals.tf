# ===========================================================================
# Data-driven API registration.
#
# Every folder under apis/ that contains an api.yaml is an API. Terraform reads
# the YAML natively (yamldecode), so there is no preprocessing step and no
# hand-maintained map: adding apis/<name>/api.yaml is the registration.
#
# CI validates each api.yaml against schemas/api.schema.json BEFORE Terraform
# runs, so a typo fails with a readable message instead of a yamldecode error.
# ===========================================================================

locals {
  apis_root = "${path.module}/../../../apis"

  # ---- discovery -----------------------------------------------------------
  api_dirs = toset([for f in fileset(local.apis_root, "*/api.yaml") : dirname(f)])

  discovered = {
    for dir in local.api_dirs : dir => yamldecode(file("${local.apis_root}/${dir}/api.yaml"))
  }

  # Environment gate: dev deploys everything discovered; prod lists APIs
  # explicitly in terraform.tfvars, which is the promotion step.
  selected = var.enabled_apis == null ? local.discovered : {
    for dir, cfg in local.discovered : dir => cfg if contains(var.enabled_apis, dir)
  }

  # ---- normalisation: apply defaults so the rest of the layer is typed -------
  apis = {
    for dir, cfg in local.selected : dir => {
      dir                   = dir
      name                  = cfg.name
      display_name          = cfg.displayName
      description           = try(cfg.description, null)
      path                  = cfg.path
      version               = try(cfg.version, "v1")
      version_set           = try(cfg.versionSet, cfg.name)
      revision              = try(cfg.revision, 1)
      product               = try(cfg.product, "internal-apis")
      subscription_required = try(cfg.subscriptionRequired, false)
      owner                 = try(cfg.owner, null)
      openapi_file          = "${local.apis_root}/${dir}/${try(cfg.openapi, "openapi.yaml")}"
      policy_file           = "${local.apis_root}/${dir}/${try(cfg.policy, "policies/inbound.xml")}"

      auth = {
        type            = try(cfg.authentication.type, "entra")
        audience        = try(cfg.authentication.audience, cfg.name)
        roles           = try(cfg.authentication.roles, {})
        required_roles  = try(cfg.authentication.requiredRoles, keys(try(cfg.authentication.roles, {})))
        write_roles     = try(cfg.authentication.writeRoles, [])
        allowed_clients = try(cfg.authentication.allowedClients, ["agent"])
      }

      rate_limit = {
        calls          = try(cfg.rateLimit.calls, 100)
        renewal_period = try(cfg.rateLimit.renewalPeriod, 60)
      }

      backend = {
        # app_service : this layer creates a web app on the shared plan
        # external    : the team runs the backend elsewhere; url or urlVariable required
        # mock        : no backend; APIM returns OpenAPI examples (dev only)
        type         = try(cfg.backend.type, "app_service")
        url          = try(cfg.backend.url, null)
        url_variable = try(cfg.backend.urlVariable, try(cfg.backendUrlVariable, null))
      }

      diagnostics = {
        enabled             = try(cfg.diagnostics.enabled, true)
        sampling_percentage = try(cfg.diagnostics.samplingPercentage, 100)
      }
    }
  }

  # ---- derived sets ----------------------------------------------------------
  version_sets      = distinct([for a in local.apis : a.version_set])
  apis_with_web_app = { for k, a in local.apis : k => a if a.backend.type == "app_service" }
  apis_with_entra   = { for k, a in local.apis : k => a if a.auth.type == "entra" }

  # Shared client identities that api.yaml may reference under allowedClients.
  clients = {
    agent = local.platform.agent_client_principal_id
  }

  # Backend URL precedence: tfvars override > api.yaml url > web app created here > mock placeholder
  backend_urls = {
    for k, a in local.apis : k => (
      a.backend.url_variable != null && lookup(var.backend_urls, coalesce(a.backend.url_variable, "-"), null) != null
      ? var.backend_urls[a.backend.url_variable]
      : a.backend.url != null
      ? a.backend.url
      : a.backend.type == "app_service"
      ? module.backend_app[k].url
      : "https://${a.name}.mock.invalid"
    )
  }
}

# ---------------------------------------------------------------------------
# The shared platform, by reference. Nothing here creates APIM.
# ---------------------------------------------------------------------------

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
  platform = data.terraform_remote_state.platform.outputs

  apim_name                = local.platform.apim_name
  apim_resource_group_name = local.platform.apim_resource_group_name
}
