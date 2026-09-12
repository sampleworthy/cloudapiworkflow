# Remote state for the DEV platform environment (Terraform-owned Azure platform).
#
# Storage account created by terraform/bootstrap. Access is Entra-only
# (shared keys disabled); the deployer needs Storage Blob Data Contributor on
# the "platform" container, which bootstrap grants. Each layer has its own
# container so the API deployer can be given read-only access to this one.
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-cloudapiworkflow-state"
    storage_account_name = "stcawstate4k7m"
    container_name       = "platform"
    key                  = "dev.tfstate"
    use_azuread_auth     = true
  }
}
