# PROD platform. Same code as dev; only these values differ.
#   * StandardV2 APIM with outbound VNet integration
#   * private endpoints for Key Vault and every backend, public access off
#   * purge protection on, longer retention, no ingestion cap
# subscription_id comes from TF_VAR_subscription_id (the prod subscription).
environment         = "prod"
location            = "eastus2"
resource_group_name = "rg-cloudapiworkflow"
name_prefix         = "cloudapiworkflow"
github_repository   = "sampleworthy/cloudapiworkflow"

apim_sku_name         = "StandardV2_1"
apim_publisher_name   = "Cloud API Workflow Platform Team"
apim_publisher_email  = "platform-team@example.com"
apim_vnet_integration = true

api_app_roles = {
  "Skills.Read"  = "Read the skills catalogue"
  "Orders.Read"  = "Read orders"
  "Orders.Write" = "Create and update orders"
}

demo_clients = {
  agent = {
    description = "Demo AI agent / service caller with real permissions."
    roles       = ["Skills.Read", "Orders.Read"]
  }
  unprivileged = {
    description = "Valid identity with no application permissions; proves 403 is enforced."
    roles       = []
  }
}

backend_apps               = ["skills-api", "orders-api"]
app_service_plan_sku       = "P1v3"
enable_private_endpoints   = true
key_vault_purge_protection = true
log_retention_days         = 90
log_daily_quota_gb         = -1

tags = {
  project    = "cloudapiworkflow"
  costCenter = "api-platform"
}
