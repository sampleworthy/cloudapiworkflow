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

variable "enabled_apis" {
  description = "Folder names under apis/ to deploy in this environment. null = every discovered API (dev). Prod lists them explicitly as the promotion gate."
  type        = list(string)
  default     = null
}

variable "backend_urls" {
  description = "Overrides for APIs whose api.yaml declares backend.urlVariable, keyed by that variable name. Lets an environment point an API at a backend it does not create."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for u in values(var.backend_urls) : can(regex("^https://", u))])
    error_message = "All backend URLs must be https."
  }
}

variable "tags" {
  type = map(string)
  default = {
    project = "cloudapiworkflow"
  }
}
