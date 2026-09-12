terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Authentication: OIDC in CI (ARM_USE_OIDC=true), Azure CLI locally. The API
# deployer identity holds API Management Service Contributor + Website
# Contributor on rg-cloudapiworkflow and read-only access to platform state.
provider "azurerm" {
  features {}

  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

provider "azuread" {}
