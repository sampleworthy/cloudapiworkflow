# ---------------------------------------------------------------------------
# Bootstrap layer
#
# Creates the things every other layer depends on and that no pipeline should
# be able to change:
#   1. the Terraform state storage account (one container per layer)
#   2. the platform resource group (empty; the platform layer imports it)
#   3. one deployer identity per (layer, environment) with GitHub OIDC
#      federated credentials and least-privilege RBAC
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

locals {
  environments = {
    dev = {
      github_environment = "development"
      subscription_id    = var.subscription_id
      allow_pr_plan      = true
    }
    prod = {
      github_environment = "production"
      subscription_id    = var.prod_subscription_id
      allow_pr_plan      = false
    }
  }

  # (layer, environment) pairs -> one service principal each
  deployers = merge([
    for env, cfg in local.environments : {
      "platform-${env}" = merge(cfg, { layer = "platform", env = env })
      "api-${env}"      = merge(cfg, { layer = "api", env = env })
    }
  ]...)

  # Federated credential subjects GitHub will present for each deployer.
  # environment:* is only issued to jobs running inside that GitHub environment,
  # which is where approval gates live. pull_request lets PR plans run for dev.
  federated_subjects = {
    for key, d in local.deployers : key => concat(
      ["repo:${var.github_repository}:environment:${d.github_environment}"],
      d.allow_pr_plan ? ["repo:${var.github_repository}:pull_request"] : []
    )
  }
}

# ---------------------------------------------------------------------------
# Resource groups
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "state" {
  name     = var.state_resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "platform" {
  name     = var.platform_resource_group_name
  location = var.location
  tags = merge(var.tags, {
    layer = "platform"
    note  = "created-by-bootstrap-owned-by-platform-layer"
  })

  lifecycle {
    # The platform layer imports and manages this group. Bootstrap must never
    # tear it down underneath it.
    prevent_destroy = true
    ignore_changes  = [tags]
  }
}

# ---------------------------------------------------------------------------
# Terraform state storage
# ---------------------------------------------------------------------------

# The account name is an input rather than a random suffix on purpose: every
# backend.tf in the repository must reference it as a literal (backend blocks
# cannot read variables), so the name has to be decided before bootstrap runs.
# Check availability first:  az storage account check-name -n <name>
resource "azurerm_storage_account" "tfstate" {
  name                = var.state_storage_account_name
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"

  # Identity-only access. No shared keys, no SAS, no anonymous blobs.
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  default_to_oauth_authentication = true

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "layers" {
  for_each = toset(["bootstrap", "platform", "api-onboarding"])

  name                  = each.key
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# The human running bootstrap needs data-plane access to migrate its own state.
resource "azurerm_role_assignment" "bootstrap_operator_state" {
  scope                = azurerm_storage_container.layers["bootstrap"].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Deployer identities (GitHub OIDC -> Entra -> Azure RBAC)
# ---------------------------------------------------------------------------

resource "azuread_application" "deployer" {
  for_each = local.deployers

  display_name = "sp-cloudapiworkflow-${each.key}"
  description  = "GitHub Actions deployer for the ${each.value.layer} Terraform layer, ${each.value.env} environment. Authenticates with workload identity federation only; no credentials are issued."
  owners       = [data.azuread_client_config.current.object_id]

  tags = ["cloudapiworkflow", each.value.layer, each.value.env, "github-oidc"]
}

resource "azuread_service_principal" "deployer" {
  for_each = local.deployers

  client_id                    = azuread_application.deployer[each.key].client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]

  tags = ["cloudapiworkflow", each.value.layer, each.value.env, "github-oidc"]
}

resource "azuread_application_federated_identity_credential" "github" {
  for_each = {
    for pair in flatten([
      for key, subjects in local.federated_subjects : [
        for s in subjects : { key = key, subject = s }
      ]
    ]) : "${pair.key}|${pair.subject}" => pair
  }

  application_id = azuread_application.deployer[each.value.key].id
  display_name   = replace(replace(each.value.subject, "repo:${var.github_repository}:", "github-"), ":", "-")
  description    = "GitHub Actions OIDC: ${each.value.subject}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = each.value.subject
}

# ---------------------------------------------------------------------------
# Azure RBAC - dev only unless a prod subscription is supplied
# ---------------------------------------------------------------------------

locals {
  rbac_enabled = { for key, d in local.deployers : key => d.subscription_id != null }

  platform_rg_scope = azurerm_resource_group.platform.id
}

# Platform deployer: owns everything inside rg-cloudapiworkflow, including the
# RBAC it hands out to managed identities and the API deployer.
resource "azurerm_role_assignment" "platform_contributor" {
  for_each = { for k, d in local.deployers : k => d if d.layer == "platform" && local.rbac_enabled[k] }

  scope                = local.platform_rg_scope
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deployer[each.key].object_id
}

resource "azurerm_role_assignment" "platform_uaa" {
  for_each = { for k, d in local.deployers : k => d if d.layer == "platform" && local.rbac_enabled[k] }

  scope                = local.platform_rg_scope
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.deployer[each.key].object_id
}

resource "azurerm_role_assignment" "platform_state" {
  for_each = { for k, d in local.deployers : k => d if d.layer == "platform" && local.rbac_enabled[k] }

  scope                = azurerm_storage_container.layers["platform"].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.deployer[each.key].object_id
}

# API deployer: may manage APIs inside the existing APIM instance and the
# backend web apps, and nothing else in the group.
resource "azurerm_role_assignment" "api_reader" {
  for_each = { for k, d in local.deployers : k => d if d.layer == "api" && local.rbac_enabled[k] }

  scope                = local.platform_rg_scope
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.deployer[each.key].object_id
}

resource "azurerm_role_assignment" "api_apim_contributor" {
  for_each = { for k, d in local.deployers : k => d if d.layer == "api" && local.rbac_enabled[k] }

  scope                = local.platform_rg_scope
  role_definition_name = "API Management Service Contributor"
  principal_id         = azuread_service_principal.deployer[each.key].object_id
}

resource "azurerm_role_assignment" "api_website_contributor" {
  for_each = { for k, d in local.deployers : k => d if d.layer == "api" && local.rbac_enabled[k] }

  scope                = local.platform_rg_scope
  role_definition_name = "Website Contributor"
  principal_id         = azuread_service_principal.deployer[each.key].object_id
}

resource "azurerm_role_assignment" "api_state" {
  for_each = { for k, d in local.deployers : k => d if d.layer == "api" && local.rbac_enabled[k] }

  scope                = azurerm_storage_container.layers["api-onboarding"].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.deployer[each.key].object_id
}

# Read-only on the platform state so terraform_remote_state can resolve APIM.
resource "azurerm_role_assignment" "api_platform_state_reader" {
  for_each = { for k, d in local.deployers : k => d if d.layer == "api" && local.rbac_enabled[k] }

  scope                = azurerm_storage_container.layers["platform"].id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azuread_service_principal.deployer[each.key].object_id
}

# ---------------------------------------------------------------------------
# Microsoft Graph application permissions
#
# Both layers create Entra app registrations (the platform creates the shared
# agent client; the API layer creates one resource app per API). OwnedBy keeps
# each identity limited to the registrations it created itself.
# ---------------------------------------------------------------------------

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

locals {
  graph_roles = {
    platform = [
      "Application.ReadWrite.OwnedBy", # create/manage the shared agent client app it owns
      "Application.Read.All",          # resolve the API deployer SP and the APIM managed identity
    ]
    api = [
      "Application.ReadWrite.OwnedBy",   # create/manage the per-API resource apps it owns
      "Application.Read.All",            # resolve the shared agent client and APIM identity
      "AppRoleAssignment.ReadWrite.All", # grant the agent client roles on each API
    ]
  }

  graph_role_assignments = {
    for pair in flatten([
      for key, d in local.deployers : [
        for role in local.graph_roles[d.layer] : { key = key, role = role }
      ]
    ]) : "${pair.key}|${pair.role}" => pair
  }
}

resource "azuread_app_role_assignment" "graph" {
  for_each = local.graph_role_assignments

  principal_object_id = azuread_service_principal.deployer[each.value.key].object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value.role]
}
