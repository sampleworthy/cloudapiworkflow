output "account_id" {
  value = azurerm_cognitive_account.this.id
}

output "account_name" {
  value = azurerm_cognitive_account.this.name
}

output "account_endpoint" {
  value = azurerm_cognitive_account.this.endpoint
}

output "openai_endpoint" {
  description = "OpenAI-compatible endpoint the APIM model API forwards to."
  value       = "https://${azurerm_cognitive_account.this.custom_subdomain_name}.openai.azure.com"
}

output "account_identity_principal_id" {
  value = azurerm_cognitive_account.this.identity[0].principal_id
}

output "project_id" {
  value = azurerm_cognitive_account_project.this.id
}

output "project_name" {
  value = azurerm_cognitive_account_project.this.name
}

output "project_endpoint" {
  description = "Endpoint for AIProjectClient (agents, responses)."
  value       = try(azurerm_cognitive_account_project.this.endpoints["AI Foundry API"], "https://${azurerm_cognitive_account.this.custom_subdomain_name}.services.ai.azure.com/api/projects/${azurerm_cognitive_account_project.this.name}")
}

output "project_identity_principal_id" {
  description = "Managed identity the agent runs as; granted app roles on the API resource app."
  value       = azurerm_cognitive_account_project.this.identity[0].principal_id
}

output "model_deployment_name" {
  value = azurerm_cognitive_deployment.model.name
}
