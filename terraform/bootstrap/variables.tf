variable "subscription_id" {
  description = "Subscription that hosts the state storage and the dev platform."
  type        = string
}

variable "location" {
  description = "Azure region for bootstrap resources."
  type        = string
  default     = "eastus2"
}

variable "github_repository" {
  description = "GitHub repository in owner/name form. Used for the OIDC federated credential subjects."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in owner/name form."
  }
}

variable "platform_resource_group_name" {
  description = "Resource group that the platform layer will own. Created here so RBAC can be scoped to it before the platform identity exists; the platform layer imports it."
  type        = string
  default     = "rg-cloudapiworkflow"
}

variable "state_resource_group_name" {
  description = "Resource group for Terraform state and deployer identities. Kept separate so a platform destroy can never remove state."
  type        = string
  default     = "rg-cloudapiworkflow-state"
}

variable "state_storage_account_name" {
  description = "Globally unique name of the Terraform state storage account. Referenced literally by every backend.tf, so it is chosen up front rather than generated."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.state_storage_account_name))
    error_message = "Storage account names are 3-24 lowercase letters and digits."
  }
}

variable "prod_subscription_id" {
  description = "Subscription for the production environment. When null, the prod identities are created but receive no Azure RBAC (prod is configuration-only)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every bootstrap resource."
  type        = map(string)
  default = {
    project   = "cloudapiworkflow"
    layer     = "bootstrap"
    managedBy = "terraform"
  }
}
