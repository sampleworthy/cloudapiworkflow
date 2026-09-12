variable "name" {
  description = "Foundry resource name; also the custom subdomain (globally unique, lowercase, letters/digits/dashes)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be lowercase letters, digits and dashes."
  }
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "project_name" {
  type = string
}

variable "project_display_name" {
  type = string
}

variable "project_description" {
  type    = string
  default = "Foundry project hosting the platform's agents."
}

variable "model" {
  description = "The single model deployment for the demo."
  type = object({
    deployment_name = optional(string, "gpt-4.1-mini")
    name            = optional(string, "gpt-4.1-mini")
    version         = optional(string, "2025-04-14")
    sku             = optional(string, "GlobalStandard")
    capacity        = optional(number, 10) # thousands of tokens per minute
  })
  default = {}
}

variable "public_network_access_enabled" {
  type    = bool
  default = true
}

variable "private_endpoint_subnet_id" {
  type    = string
  default = null
}

variable "private_dns_zone_ids" {
  description = "privatelink.cognitiveservices.azure.com, privatelink.openai.azure.com, privatelink.services.ai.azure.com"
  type        = list(string)
  default     = []
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

variable "tags" {
  type    = map(string)
  default = {}
}
