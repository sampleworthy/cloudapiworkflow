# Remote state for DEV API onboarding. Separate container and key from the
# platform layer: the API deployer can write here but only read "platform".
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-cloudapiworkflow-state"
    storage_account_name = "stcawstate4k7m"
    container_name       = "api-onboarding"
    key                  = "dev.tfstate"
    use_azuread_auth     = true
  }
}
