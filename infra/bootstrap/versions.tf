terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.12.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "= 3.10.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "= 2.9.1"
    }
  }

  # Bootstrap keeps LOCAL state on purpose: it creates the remote state storage that the other
  # stacks use. The state file (git-ignored) holds no secrets: no client secrets are created.
  # Every resource here can be re-imported if the file is lost. See docs/adr/0003.
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  storage_use_azuread             = true
  resource_provider_registrations = "none"
}

provider "azuread" {
  tenant_id = var.tenant_id
}
