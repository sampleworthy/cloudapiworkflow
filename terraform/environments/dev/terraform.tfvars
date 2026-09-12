# DEV platform. Cost-conscious: Consumption APIM, one B1 plan, public
# endpoints guarded by identity. subscription_id comes from TF_VAR_subscription_id.
environment         = "dev"
location            = "eastus2"
resource_group_name = "rg-cloudapiworkflow"
name_prefix         = "cloudapiworkflow"
github_repository   = "sampleworthy/cloudapiworkflow"

apim_sku_name         = "Consumption_0"
apim_publisher_name   = "Cloud API Workflow Platform Team"
apim_publisher_email  = "platform-team@example.com"
apim_vnet_integration = false

# Application permissions exposed by the API resource app. API policies in
# apim/artifacts require these by name; adding a role here is a platform PR.
api_app_roles = {
  "Skills.Read"  = "Read the skills catalogue"
  "Orders.Read"  = "Read orders"
  "Orders.Write" = "Create and update orders"
  "Models.Use"   = "Call approved AI models through the gateway"
}

# Foundry: one small model deployment; the project identity may read Skills and Orders.
foundry_model = {
  deployment_name = "gpt-4.1-mini"
  name            = "gpt-4.1-mini"
  version         = "2025-04-14"
  sku             = "GlobalStandard"
  capacity        = 10
}
agent_app_roles             = ["Skills.Read", "Orders.Read"]
agent_deployer_display_name = "sp-cloudapiworkflow-agent-deployer-dev"

demo_clients = {
  agent = {
    description = "Demo AI agent / service caller with real permissions."
    roles       = ["Skills.Read", "Orders.Read", "Models.Use"]
  }
  unprivileged = {
    description = "Valid identity with no application permissions; proves 403 is enforced."
    roles       = []
  }
}

backend_apps               = ["skills-api", "orders-api"]
app_service_plan_sku       = "B1"
enable_private_endpoints   = false
key_vault_purge_protection = false
log_retention_days         = 30
log_daily_quota_gb         = 1

tags = {
  project    = "cloudapiworkflow"
  costCenter = "platform-demo"
}
