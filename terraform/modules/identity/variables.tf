variable "name" {
  description = "Path segment of the identifier URI, e.g. orders-api-dev."
  type        = string
}

variable "display_name" {
  type = string
}

variable "description" {
  type    = string
  default = null
}

variable "tenant_id" {
  type = string
}

variable "app_roles" {
  description = "Map of role value (e.g. Orders.Read) to description."
  type        = map(string)

  validation {
    condition     = alltrue([for r in keys(var.app_roles) : can(regex("^[A-Z][A-Za-z]+\\.[A-Z][A-Za-z]+$", r))])
    error_message = "App role values must look like Resource.Action (e.g. Orders.Read)."
  }
}

variable "client_grants" {
  description = "Client identities to grant roles to: { key = { principal_object_id, roles = [...] } }."
  type = map(object({
    principal_object_id = string
    roles               = list(string)
  }))
  default = {}
}

variable "owners" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = list(string)
  default = []
}
