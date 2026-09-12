output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "vnet_name" {
  value = azurerm_virtual_network.this.name
}

output "apim_subnet_id" {
  value = azurerm_subnet.apim.id
}

output "app_integration_subnet_id" {
  value = azurerm_subnet.app_integration.id
}

output "private_endpoint_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}

output "private_dns_zone_ids" {
  description = "Map of zone name to zone id."
  value       = { for k, z in azurerm_private_dns_zone.zones : k => z.id }
}
