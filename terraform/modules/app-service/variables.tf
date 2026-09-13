variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "service_plan_id" {
  description = "Shared App Service Plan owned by the platform layer."
  type        = string
}

variable "python_version" {
  type    = string
  default = "3.12"
}

variable "startup_command" {
  type    = string
  default = "python -m gunicorn -w 2 -k uvicorn.workers.UvicornWorker app.main:app --bind 0.0.0.0:8000"
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "always_on" {
  type    = bool
  default = true
}

variable "public_network_access_enabled" {
  type    = bool
  default = true
}

variable "vnet_integration_subnet_id" {
  type    = string
  default = null
}

variable "enable_private_endpoint" {
  description = "Create a private endpoint (needs private_endpoint_subnet_id). A boolean rather than a null-check so count is known at plan time."
  type        = bool
  default     = false
}

variable "private_endpoint_subnet_id" {
  type    = string
  default = null
}

variable "private_dns_zone_id" {
  type    = string
  default = null
}

variable "allowed_ip_addresses" {
  description = "APIM egress IPs to allow at the network layer. Empty on tiers without static IPs."
  type        = list(string)
  default     = []
}

variable "auth_client_id" {
  description = "Client id of this API's own Entra app registration; Easy Auth validates tokens issued for it."
  type        = string
}

variable "auth_tenant_endpoint" {
  description = "OpenID issuer, e.g. https://sts.windows.net/<tenant-id>/ for v1 access tokens."
  type        = string
}

variable "auth_allowed_client_ids" {
  description = "Client ids permitted to call this app. Normally only the APIM managed identity."
  type        = list(string)
}

variable "auth_allowed_audiences" {
  type = list(string)
}

variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}

variable "enable_diagnostics" {
  description = "Send AppService* logs to log_analytics_workspace_id."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  type    = string
  default = null
}

variable "app_settings" {
  type    = map(string)
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
