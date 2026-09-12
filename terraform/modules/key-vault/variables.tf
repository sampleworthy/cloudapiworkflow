variable "name" {
  type = string

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 24
    error_message = "Key Vault names must be 3-24 characters."
  }
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "purge_protection_enabled" {
  description = "Cannot be turned off once enabled. True in prod; false in dev so the demo can be torn down cleanly."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  type    = bool
  default = true
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for a private endpoint. Null disables the endpoint."
  type        = string
  default     = null
}

variable "private_dns_zone_id" {
  type    = string
  default = null
}

variable "secrets_officer_principal_ids" {
  type    = list(string)
  default = []
}

variable "secrets_user_principal_ids" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
