variable "log_analytics_name" {
  type = string
}

variable "app_insights_name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "retention_in_days" {
  type    = number
  default = 30
}

variable "daily_quota_gb" {
  description = "Daily ingestion cap in GB. -1 disables the cap. Keep a cap in dev so a runaway logger cannot create a bill."
  type        = number
  default     = 1
}

variable "sampling_percentage" {
  type    = number
  default = 100
}

variable "tags" {
  type    = map(string)
  default = {}
}
