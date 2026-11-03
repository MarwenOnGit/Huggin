terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.12.0"
    }
  }

  # Partial config: make init STACK=sentinel passes ../shared/backend.hcl and key=sentinel.tfstate.
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id                 = local.shared.subscription_id
  tenant_id                       = local.shared.tenant_id
  storage_use_azuread             = true
  resource_provider_registrations = "none"
}
