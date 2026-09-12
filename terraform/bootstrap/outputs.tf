output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = var.subscription_id
}

output "tfstate_resource_group_name" {
  value = azurerm_resource_group.state.name
}

output "tfstate_storage_account_name" {
  description = "Put this value in every backend.tf and in the TFSTATE_STORAGE_ACCOUNT GitHub variable."
  value       = azurerm_storage_account.tfstate.name
}

output "platform_resource_group_name" {
  value = azurerm_resource_group.platform.name
}

output "platform_resource_group_id" {
  description = "Import this into terraform/platform/<env> on first run (see the import block there)."
  value       = azurerm_resource_group.platform.id
}

output "deployer_client_ids" {
  description = "GitHub environment variables: AZURE_PLATFORM_CLIENT_ID and AZURE_API_CLIENT_ID per environment."
  value       = { for k, app in azuread_application.deployer : k => app.client_id }
}

output "deployer_object_ids" {
  value = { for k, sp in azuread_service_principal.deployer : k => sp.object_id }
}

output "federated_subjects" {
  value = local.federated_subjects
}
