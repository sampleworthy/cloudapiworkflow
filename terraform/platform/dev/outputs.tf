# Contract consumed by terraform/api-onboarding/<env> via terraform_remote_state.
# Adding an output here is backwards compatible; renaming one is a breaking
# change for the onboarding layer and must be coordinated.

output "environment" {
  value = var.environment
}

output "location" {
  value = azurerm_resource_group.main.location
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "resource_suffix" {
  description = "Suffix used for globally unique names; the onboarding layer reuses it for web apps."
  value       = random_string.suffix.result
}

# --- APIM: the shared instance the onboarding layer adds APIs to ------------

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

output "apim_public_ip_addresses" {
  value = module.apim.public_ip_addresses
}

output "apim_logger_id" {
  value = module.apim.logger_id
}

output "product_ids" {
  description = "Products APIs may attach to: internal-apis, partner-apis, agent-apis."
  value       = module.apim.product_ids
}

# --- Backends, network, monitoring ---------------------------------------------

output "app_service_plan_id" {
  value = azurerm_service_plan.backends.id
}

output "app_integration_subnet_id" {
  value = module.networking.app_integration_subnet_id
}

output "private_endpoint_subnet_id" {
  value = module.networking.private_endpoint_subnet_id
}

output "private_dns_zone_ids" {
  value = module.networking.private_dns_zone_ids
}

output "enable_private_endpoints" {
  value = var.enable_private_endpoints
}

output "log_analytics_workspace_id" {
  value = module.monitoring.log_analytics_workspace_id
}

output "app_insights_connection_string" {
  value     = module.monitoring.app_insights_connection_string
  sensitive = true
}

# --- Identity ----------------------------------------------------------------

output "key_vault_name" {
  value = module.key_vault.name
}

output "key_vault_uri" {
  value = module.key_vault.vault_uri
}

output "agent_client_id" {
  description = "Client id of the shared demo M2M caller."
  value       = azuread_application.agent_client.client_id
}

output "agent_client_principal_id" {
  description = "Service principal object id of the agent client; the onboarding layer grants it app roles."
  value       = azuread_service_principal.agent_client.object_id
}

output "agent_client_secret_name" {
  value = azurerm_key_vault_secret.agent_client_secret.name
}
