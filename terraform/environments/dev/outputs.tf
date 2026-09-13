# Values APIOps and the deployment workflows need. terraform-deploy publishes
# the github_variables map as repository variables (suffixed _DEV / _PROD) so
# the publisher and test jobs never read Terraform state.

output "environment" {
  value = var.environment
}

output "tenant_id" {
  value = local.tenant_id
}

output "resource_suffix" {
  value = random_string.suffix.result
}

# --- APIM --------------------------------------------------------------------

output "apim_name" {
  value = module.apim.name
}

output "apim_id" {
  value = module.apim.id
}

output "apim_resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "apim_gateway_url" {
  value = module.apim.gateway_url
}

output "apim_sku_name" {
  value = module.apim.sku_name
}

output "apim_identity_principal_id" {
  value = module.apim.identity_principal_id
}

output "apim_identity_client_id" {
  description = "Client id of the APIM managed identity; backends allow-list this."
  value       = data.azuread_service_principal.apim_identity.client_id
}

# --- Monitoring ----------------------------------------------------------------

output "app_insights_id" {
  value = module.monitoring.app_insights_id
}

output "app_insights_name" {
  value = module.monitoring.app_insights_name
}

output "log_analytics_workspace_id" {
  value = module.monitoring.log_analytics_workspace_id
}

output "app_insights_connection_string" {
  value     = module.monitoring.app_insights_connection_string
  sensitive = true
}

# --- Key Vault -----------------------------------------------------------------

output "key_vault_name" {
  value = module.key_vault.name
}

output "key_vault_uri" {
  value = module.key_vault.vault_uri
}

output "appinsights_secret_id" {
  description = "Key Vault secret identifier the APIOps logger named value points at."
  value       = azurerm_key_vault_secret.appinsights_connection_string.versionless_id
}

# --- Identity ------------------------------------------------------------------

output "api_audience" {
  description = "Token audience every API expects: api://<tenant-id>/cloudapiworkflow-<env>."
  value       = module.api_resource_app.identifier_uri
}

output "api_resource_app_client_id" {
  value = module.api_resource_app.client_id
}

output "demo_client_ids" {
  value = { for k, app in azuread_application.demo_client : k => app.client_id }
}

# --- Backends ------------------------------------------------------------------

output "backend_urls" {
  description = "Per-API backend URLs; APIOps configuration.<env>.yaml overrides use these."
  value       = { for k, app in module.backend_app : k => app.url }
}

# --- Foundry -------------------------------------------------------------------

output "foundry_account_name" {
  value = module.foundry.account_name
}

output "foundry_project_endpoint" {
  value = module.foundry.project_endpoint
}

output "foundry_openai_endpoint" {
  value = module.foundry.openai_endpoint
}

output "foundry_model_deployment" {
  value = module.foundry.model_deployment_name
}

output "agent_identity_principal_id" {
  description = "Object id of the Foundry project identity the agent runs as."
  value       = module.foundry.project_identity_principal_id
}

# --- For GitHub variables (flat, non-secret) -------------------------------------

output "github_variables" {
  description = "Published by terraform-deploy as repository variables <KEY>_<ENV>."
  value = merge(
    {
      APIM_NAME                          = module.apim.name
      APIM_GATEWAY_URL                   = module.apim.gateway_url
      APIM_RESOURCE_GROUP                = azurerm_resource_group.main.name
      API_AUDIENCE                       = module.api_resource_app.identifier_uri
      AGENT_CLIENT_ID                    = azuread_application.demo_client["agent"].client_id
      UNPRIVILEGED_CLIENT_ID             = azuread_application.demo_client["unprivileged"].client_id
      APPINSIGHTS_ID                     = module.monitoring.app_insights_id
      APPINSIGHTS_SECRET_ID              = azurerm_key_vault_secret.appinsights_connection_string.versionless_id
      KEY_VAULT_NAME                     = module.key_vault.name
      FOUNDRY_PROJECT_ENDPOINT           = module.foundry.project_endpoint
      FOUNDRY_OPENAI_ENDPOINT            = module.foundry.openai_endpoint
      FOUNDRY_MODEL_DEPLOYMENT           = module.foundry.model_deployment_name
      AGENT_IDENTITY_PRINCIPAL_ID        = module.foundry.project_identity_principal_id
      AGENT_IDENTITY_CLIENT_ID           = data.azuread_service_principal.agent_identity.client_id
      FOUNDRY_ACCOUNT_IDENTITY_CLIENT_ID = data.azuread_service_principal.foundry_account_identity.client_id
      LOG_ANALYTICS_WORKSPACE_ID         = module.monitoring.log_analytics_workspace_customer_id
    },
    { for k, app in module.backend_app : "BACKEND_URL_${upper(replace(k, "-", "_"))}" => app.url }
  )
}
