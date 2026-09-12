variable "subscription_id" {
  description = "Target subscription. Supplied by CI as TF_VAR_subscription_id; never committed."
  type        = string
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "resource_group_name" {
  type    = string
  default = "rg-cloudapiworkflow"
}

variable "name_prefix" {
  description = "Base for every resource name (apim-<prefix>-<suffix>, kv-<prefix>-<suffix>, ...)."
  type        = string
  default     = "cloudapiworkflow"
}

variable "github_repository" {
  description = "owner/name of this repository; used for the agent client's federated credential."
  type        = string
}

variable "api_deployer_display_name" {
  description = "Display name of the API-layer deployer service principal created by bootstrap."
  type        = string
}

# --- APIM ------------------------------------------------------------------

variable "apim_sku_name" {
  type    = string
  default = "Consumption_0"
}

variable "apim_publisher_name" {
  type = string
}

variable "apim_publisher_email" {
  type = string
}

variable "apim_vnet_integration" {
  description = "Integrate APIM with snet-apim. Requires a V2 or classic tier; ignored on Consumption."
  type        = bool
  default     = false
}

variable "apim_diagnostic_sampling_percentage" {
  type    = number
  default = 100
}

# --- Backends, vault, logs ----------------------------------------------------

variable "app_service_plan_sku" {
  type    = string
  default = "B1"
}

variable "enable_private_endpoints" {
  description = "Private endpoints for Key Vault (and, via the onboarding layer, backends). Prod only."
  type        = bool
  default     = false
}

variable "key_vault_purge_protection" {
  type    = bool
  default = false
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "log_daily_quota_gb" {
  type    = number
  default = 1
}

variable "tags" {
  type = map(string)
  default = {
    project = "cloudapiworkflow"
  }
}
