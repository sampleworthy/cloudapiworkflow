# --- Where the API lives (from platform remote state, never hard-coded) -----

variable "apim_name" {
  description = "Name of the existing shared APIM instance."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the existing shared APIM instance."
  type        = string
}

variable "logger_id" {
  description = "APIM logger id from the platform layer. Null disables diagnostics."
  type        = string
  default     = null
}

# --- Identity of the API ----------------------------------------------------

variable "api_name" {
  description = "APIM API id, e.g. orders-api-v1. Lowercase letters, digits and dashes."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,78}[a-z0-9])?$", var.api_name))
    error_message = "api_name must be 1-80 chars of lowercase letters, digits and dashes."
  }
}

variable "display_name" {
  type = string
}

variable "description" {
  type    = string
  default = null
}

variable "path" {
  description = "URL suffix under the gateway, e.g. orders."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9/-]*$", var.path))
    error_message = "path must be lowercase and must not start with a slash."
  }
}

variable "api_version" {
  description = "Version identifier (v1, v2). Applied only when version_set_id is set."
  type        = string
  default     = "v1"
}

variable "version_set_id" {
  description = "APIM version set id. Null creates an un-versioned API."
  type        = string
  default     = null
}

variable "revision" {
  type    = number
  default = 1
}

# --- Contract, backend, policy ---------------------------------------------

variable "openapi_file" {
  description = "Path to the OpenAPI 3.x document (yaml or json)."
  type        = string
}

variable "policy_file" {
  description = "Path to the API policy XML. Rendered with templatefile() using the policy_vars below."
  type        = string
}

variable "policy_vars" {
  description = "Extra template variables merged over the defaults (audience, roles, backend, rate limit)."
  type        = map(any)
  default     = {}
}

variable "backend_url" {
  description = "HTTPS URL of the backend service."
  type        = string

  validation {
    condition     = can(regex("^https://", var.backend_url))
    error_message = "backend_url must be https."
  }
}

variable "backend_auth" {
  description = "How APIM authenticates to the backend. managed_identity requests a token for `audience` with the APIM system identity."
  type = object({
    type     = optional(string, "managed_identity")
    audience = optional(string, "")
  })
  default = {}
}

variable "mock_responses" {
  description = "Return OpenAPI examples instead of calling the backend (dev only for APIs whose backend lives elsewhere)."
  type        = bool
  default     = false
}

# --- Governance --------------------------------------------------------------

variable "product_ids" {
  type    = list(string)
  default = []
}

variable "subscription_required" {
  type    = bool
  default = false
}

variable "auth" {
  description = "JWT requirements enforced by the API policy."
  type = object({
    audience       = string
    audiences      = optional(list(string), [])
    required_roles = optional(list(string), [])
    write_roles    = optional(list(string), [])
  })
}

variable "rate_limit" {
  type = object({
    calls          = optional(number, 100)
    renewal_period = optional(number, 60)
  })
  default = {}
}

variable "enable_diagnostics" {
  type    = bool
  default = true
}

variable "diagnostic_sampling_percentage" {
  type    = number
  default = 100
}

variable "tags" {
  description = "Informational only: APIM APIs on Consumption do not carry ARM tags."
  type        = map(string)
  default     = {}
}
