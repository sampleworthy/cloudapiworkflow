# Remote state for the PROD platform layer.
#
# In a real estate prod state lives in the prod subscription's own storage
# account, written only by sp-cloudapiworkflow-platform-prod from the
# "production" GitHub environment (required reviewers). This demo keeps the
# same account with a separate key so the prod root is fully validated and
# planned by CI while never being applied.
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-cloudapiworkflow-state"
    storage_account_name = "stcawstate4k7m"
    container_name       = "platform"
    key                  = "prod.tfstate"
    use_azuread_auth     = true
  }
}
