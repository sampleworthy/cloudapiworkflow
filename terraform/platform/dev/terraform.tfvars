# DEV platform. Cost-conscious: Consumption APIM, one B1 plan, public
# endpoints guarded by identity. subscription_id comes from TF_VAR_subscription_id.
environment               = "dev"
location                  = "eastus2"
resource_group_name       = "rg-cloudapiworkflow"
name_prefix               = "cloudapiworkflow"
github_repository         = "sampleworthy/cloudapiworkflow"
api_deployer_display_name = "sp-cloudapiworkflow-api-dev"

apim_sku_name                       = "Consumption_0"
apim_publisher_name                 = "Cloud API Workflow Platform Team"
apim_publisher_email                = "platform-team@example.com"
apim_vnet_integration               = false
apim_diagnostic_sampling_percentage = 100

app_service_plan_sku       = "B1"
enable_private_endpoints   = false
key_vault_purge_protection = false
log_retention_days         = 30
log_daily_quota_gb         = 1

tags = {
  project    = "cloudapiworkflow"
  costCenter = "platform-demo"
}
