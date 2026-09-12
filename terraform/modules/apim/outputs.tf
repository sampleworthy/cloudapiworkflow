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

output "logger_id" {
  value = azurerm_api_management_logger.app_insights.id
}

output "product_ids" {
  description = "Map of product key to product id, for the onboarding layer."
  value       = { for k, p in azurerm_api_management_product.this : k => p.product_id }
}

output "sku_name" {
  value = azurerm_api_management.this.sku_name
}
