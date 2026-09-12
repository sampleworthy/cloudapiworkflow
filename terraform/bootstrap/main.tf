# ---------------------------------------------------------------------------
# Bootstrap layer
#
# Creates the things every other pipeline depends on and that no pipeline
# should be able to change:
#   1. the Terraform state storage account (containers: bootstrap, platform)
#   2. the platform resource group (empty; the platform layer imports it)
#   3. one federated identity per (role, environment):
#        platform          Terraform deployer (Contributor on the group)
#        apiops-publisher  writes API artifacts into the existing APIM instance
#        apiops-extractor  reads APIM configuration for drift / sync PRs
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

  roles = ["platform", "apiops-publisher", "apiops-extractor"]

  deployers = merge([
    for env, cfg in local.environments : {
      for role in local.roles : "${role}-${env}" => merge(cfg, { role = role, env = env })
    }
  ]...)

  # OIDC subjects GitHub presents. environment:* tokens are only issued to jobs
  # inside that GitHub environment (where approval gates live). The extractor
  # is read-only and runs from schedules on main, so it trusts the main ref.
  federated_subjects = {
    for key, d in local.deployers : key => (
      d.role == "apiops-extractor"
      ? ["repo:${var.github_repository}:ref:refs/heads/main", "repo:${var.github_repository}:environment:${d.github_environment}"]
      : concat(
        ["repo:${var.github_repository}:environment:${d.github_environment}"],
        d.allow_pr_plan && d.role == "platform" ? ["repo:${var.github_repository}:pull_request"] : []
      )
    )
  }

  rbac_enabled = { for key, d in local.deployers : key => d.subscription_id != null }
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
  for_each = toset(["bootstrap", "platform"])

  name                  = each.key
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "bootstrap_operator_state" {
  scope                = azurerm_storage_container.layers["bootstrap"].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Federated identities (GitHub OIDC -> Entra -> Azure RBAC)
# ---------------------------------------------------------------------------

resource "azuread_application" "deployer" {
  for_each = local.deployers

  display_name = "sp-cloudapiworkflow-${each.key}"
  description  = "GitHub Actions identity: ${each.value.role}, ${each.value.env}. Workload identity federation only; no credentials are issued."
  owners       = [data.azuread_client_config.current.object_id]
  tags         = ["cloudapiworkflow", each.value.role, each.value.env, "github-oidc"]
}

resource "azuread_service_principal" "deployer" {
  for_each = local.deployers

  client_id                    = azuread_application.deployer[each.key].client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
  tags                         = ["cloudapiworkflow", each.value.role, each.value.env, "github-oidc"]
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
  display_name   = replace(replace(replace(each.value.subject, "repo:${var.github_repository}:", "github-"), ":", "-"), "/", "-")
  description    = "GitHub Actions OIDC: ${each.value.subject}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = each.value.subject
}

# ---------------------------------------------------------------------------
# Azure RBAC (dev only unless a prod subscription is supplied)
# ---------------------------------------------------------------------------

locals {
  # role name -> list of Azure built-in roles on the platform resource group
  azure_roles = {
    platform         = ["Contributor", "User Access Administrator"]
    apiops-publisher = ["Reader", "API Management Service Contributor"]
    apiops-extractor = ["Reader", "API Management Service Reader Role"]
  }

  azure_role_assignments = {
    for pair in flatten([
      for key, d in local.deployers : [
        for r in local.azure_roles[d.role] : { key = key, role = r }
      ] if local.rbac_enabled[key]
    ]) : "${pair.key}|${pair.role}" => pair
  }
}

resource "azurerm_role_assignment" "platform_group" {
  for_each = local.azure_role_assignments

  scope                = azurerm_resource_group.platform.id
  role_definition_name = each.value.role
  principal_id         = azuread_service_principal.deployer[each.value.key].object_id
}

# Only the Terraform deployer touches state.
resource "azurerm_role_assignment" "platform_state" {
  for_each = { for k, d in local.deployers : k => d if d.role == "platform" && local.rbac_enabled[k] }

  scope                = azurerm_storage_container.layers["platform"].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.deployer[each.key].object_id
}

# ---------------------------------------------------------------------------
# Microsoft Graph application permissions. Only the platform deployer creates
# Entra objects (the API resource app and the demo clients); OwnedBy limits
# it to registrations it created itself. APIOps identities need nothing.
# ---------------------------------------------------------------------------

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

locals {
  graph_roles = {
    platform = [
      "Application.ReadWrite.OwnedBy",   # create/manage the resource app and demo clients it owns
      "Application.Read.All",            # resolve the APIM managed identity's client id
      "AppRoleAssignment.ReadWrite.All", # grant demo clients app roles on the resource app
    ]
    apiops-publisher = []
    apiops-extractor = []
  }

  graph_role_assignments = {
    for pair in flatten([
      for key, d in local.deployers : [
        for role in local.graph_roles[d.role] : { key = key, role = role }
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
