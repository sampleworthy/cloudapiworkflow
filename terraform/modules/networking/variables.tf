variable "name" {
  description = "Virtual network name."
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "address_space" {
  type    = string
  default = "10.40.0.0/16"
}

variable "apim_subnet_prefix" {
  type    = string
  default = "10.40.0.0/27"
}

variable "apim_subnet_delegate_to_web" {
  description = "Delegate snet-apim to Microsoft.Web/serverFarms. Required for StandardV2/PremiumV2 outbound integration; must be false for Developer/Premium injection."
  type        = bool
  default     = true
}

variable "app_integration_subnet_prefix" {
  type    = string
  default = "10.40.1.0/26"
}

variable "private_endpoint_subnet_prefix" {
  type    = string
  default = "10.40.2.0/26"
}

variable "private_dns_zones" {
  description = "Private DNS zones to create and link. Populated with records only when private endpoints are enabled."
  type        = list(string)
  default = [
    "privatelink.azurewebsites.net",
    "privatelink.vaultcore.azure.net",
  ]
}

variable "tags" {
  type    = map(string)
  default = {}
}
