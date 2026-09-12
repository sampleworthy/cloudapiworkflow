output "id" {
  value = azurerm_key_vault.this.id
}

output "name" {
  value = azurerm_key_vault.this.name
}

output "vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "secrets_officer_role_assignment_ids" {
  description = "Depend on this before writing secrets so RBAC has been granted."
  value       = [for r in azurerm_role_assignment.secrets_officers : r.id]
}
