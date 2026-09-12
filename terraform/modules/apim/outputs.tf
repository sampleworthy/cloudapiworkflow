output "id" {
  value = azurerm_api_management.this.id
}

output "name" {
  value = azurerm_api_management.this.name
}

output "gateway_url" {
  value = azurerm_api_management.this.gateway_url
}

output "identity_principal_id" {
  description = "Object id of the system-assigned managed identity."
  value       = azurerm_api_management.this.identity[0].principal_id
}

output "public_ip_addresses" {
  description = "Static outbound IPs (empty on Consumption and non-integrated V2 tiers)."
  value       = azurerm_api_management.this.public_ip_addresses
}

output "sku_name" {
  value = azurerm_api_management.this.sku_name
}
