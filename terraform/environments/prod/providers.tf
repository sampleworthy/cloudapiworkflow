terraform {
  required_version = ">= 1.16.0, < 2.0.0"

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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

# Authentication: in CI, ARM_USE_OIDC=true + ARM_CLIENT_ID/ARM_TENANT_ID and the
# GitHub id-token; locally, the signed-in Azure CLI user. No client secrets.
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    api_management {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }

  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

provider "azuread" {}

provider "azapi" {
  subscription_id = var.subscription_id
}
