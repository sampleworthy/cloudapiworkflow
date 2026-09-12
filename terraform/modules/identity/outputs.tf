output "client_id" {
  value = azuread_application.this.client_id
}

output "object_id" {
  value = azuread_application.this.object_id
}

output "service_principal_object_id" {
  value = azuread_service_principal.this.object_id
}

output "identifier_uri" {
  description = "The audience callers request a token for."
  value       = "api://${var.tenant_id}/${var.name}"
}

output "app_role_ids" {
  value = { for k, u in random_uuid.role : k => u.result }
}
