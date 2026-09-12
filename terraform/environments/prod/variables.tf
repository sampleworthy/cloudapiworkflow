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
  description = "owner/name of this repository; used for the demo clients' federated credentials."
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

# --- Identity ------------------------------------------------------------------

variable "api_app_roles" {
  description = "Application permissions exposed by the environment's API resource app: role value -> description. API policies in apim/artifacts require these by name."
  type        = map(string)

  validation {
    condition     = alltrue([for r in keys(var.api_app_roles) : can(regex("^[A-Z][A-Za-z]+\\.[A-Z][A-Za-z]+$", r))])
    error_message = "Roles must look like Resource.Action (e.g. Orders.Read)."
  }
}

variable "demo_clients" {
  description = "Machine-to-machine demo callers and the roles they hold. Used by post-deployment tests (401/403/200 matrix)."
  type = map(object({
    description = string
    roles       = list(string)
  }))
  default = {
    agent = {
      description = "Demo AI agent / service caller with real permissions."
      roles       = ["Skills.Read", "Orders.Read"]
    }
    unprivileged = {
      description = "Valid identity with no application permissions; proves authorization (403) is enforced."
      roles       = []
    }
  }
}

# --- Foundry / agents ------------------------------------------------------------

variable "foundry_model" {
  description = "Single model deployment for the demo (multi-model routing is an APIM backend-pool concern)."
  type = object({
    deployment_name = optional(string, "gpt-4.1-mini")
    name            = optional(string, "gpt-4.1-mini")
    version         = optional(string, "2025-04-14")
    sku             = optional(string, "GlobalStandard")
    capacity        = optional(number, 10)
  })
  default = {}
}

variable "agent_app_roles" {
  description = "App roles granted to the Foundry project identity (what agents may call through APIM). Read-only by design."
  type        = list(string)
  default     = ["Skills.Read", "Orders.Read"]
}

variable "agent_deployer_display_name" {
  description = "Display name of the agent-deployer service principal created by bootstrap."
  type        = string
}

# --- Backends, vault, logs ----------------------------------------------------

variable "backend_apps" {
  description = "Demo backend web apps to host on the shared plan (one per API team). Names double as the 'api' tag used by application-deploy."
  type        = list(string)
  default     = ["skills-api", "orders-api"]
}

variable "app_service_plan_sku" {
  type    = string
  default = "B1"
}

variable "enable_private_endpoints" {
  description = "Private endpoints for Key Vault and backends, public access off. Prod only."
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
