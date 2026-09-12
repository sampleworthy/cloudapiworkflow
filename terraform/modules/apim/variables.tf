variable "name" {
  description = "APIM service name (globally unique)."
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "publisher_name" {
  type = string
}

variable "publisher_email" {
  type = string
}

variable "sku_name" {
  description = "APIM SKU in <tier>_<units> form: Consumption_0, Developer_1, BasicV2_1, StandardV2_1, Premium_1."
  type        = string
  default     = "Consumption_0"

  validation {
    condition     = can(regex("^(Consumption_0|Developer_1|Basic_[1-2]|BasicV2_[1-9]|Standard_[1-4]|StandardV2_[1-9]|Premium_[1-9]|PremiumV2_[1-9])$", var.sku_name))
    error_message = "Unsupported APIM sku_name."
  }
}

variable "vnet_subnet_id" {
  description = "Subnet for VNet integration/injection. Ignored on Consumption."
  type        = string
  default     = null
}

variable "classic_vnet_type" {
  description = "Injection mode for Developer/Premium tiers: External or Internal."
  type        = string
  default     = "External"
}

variable "public_network_access_enabled" {
  type    = bool
  default = true
}

variable "named_values" {
  type = map(object({
    value  = string
    secret = optional(bool, false)
  }))
  default = {}
}

variable "global_policy_xml" {
  type = string
}

variable "products" {
  type = map(object({
    display_name          = string
    description           = string
    subscription_required = bool
    approval_required     = optional(bool, false)
    subscriptions_limit   = optional(number, 1)
    policy_xml            = optional(string)
  }))
}

variable "app_insights_id" {
  type = string
}

variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "diagnostic_sampling_percentage" {
  type    = number
  default = 100
}

variable "tags" {
  type    = map(string)
  default = {}
}
