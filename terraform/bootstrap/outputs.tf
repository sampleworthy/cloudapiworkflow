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
  description = "Referenced literally by terraform/environments/*/backend.tf."
  value       = azurerm_storage_account.tfstate.name
}

output "platform_resource_group_name" {
  value = azurerm_resource_group.platform.name
}

output "platform_resource_group_id" {
  description = "Imported by terraform/environments/<env> through its import block."
  value       = azurerm_resource_group.platform.id
}

output "deployer_client_ids" {
  description = "GitHub repository variables: AZURE_PLATFORM_CLIENT_ID_<ENV>, AZURE_APIOPS_PUBLISHER_CLIENT_ID_<ENV>, AZURE_APIOPS_EXTRACTOR_CLIENT_ID_<ENV>, AZURE_AGENT_DEPLOYER_CLIENT_ID_<ENV>."
  value       = { for k, app in azuread_application.deployer : k => app.client_id }
}

output "deployer_object_ids" {
  value = { for k, sp in azuread_service_principal.deployer : k => sp.object_id }
}

output "federated_subjects" {
  value = local.federated_subjects
}

output "github_variables" {
  description = "Ready-to-run commands that publish the identity ids as GitHub variables (no secrets involved)."
  value = join("\n", concat(
    ["gh variable set AZURE_TENANT_ID --body ${data.azurerm_client_config.current.tenant_id}"],
    ["gh variable set AZURE_SUBSCRIPTION_ID_DEV --body ${var.subscription_id}"],
    [for k, app in azuread_application.deployer :
      "gh variable set AZURE_${upper(replace(replace(replace(k, "-dev", ""), "-prod", ""), "-", "_"))}_CLIENT_ID_${upper(endswith(k, "-dev") ? "dev" : "prod")} --body ${app.client_id}"
    ]
  ))
}
