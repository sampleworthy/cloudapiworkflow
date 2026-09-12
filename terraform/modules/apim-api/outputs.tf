output "api_id" {
  value = azurerm_api_management_api.this.id
}

output "api_name" {
  value = azurerm_api_management_api.this.name
}

output "path" {
  description = "Gateway path including version segment when versioned."
  value       = var.version_set_id == null ? var.path : "${var.path}/${var.api_version}"
}

output "backend_id" {
  value = azurerm_api_management_backend.this.name
}

output "products" {
  value = var.product_ids
}
