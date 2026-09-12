# Remote state for PROD API onboarding. See platform/prod/backend.tf for why
# this demo shares one state account across environments.
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-cloudapiworkflow-state"
    storage_account_name = "stcawstate4k7m"
    container_name       = "api-onboarding"
    key                  = "prod.tfstate"
    use_azuread_auth     = true
  }
}
