terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.12.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1"
    }
  }

  # Partial config: make init STACK=purple passes ../shared/backend.hcl and key=purple.tfstate.
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      # Disposable vault: purge it on destroy so nothing is left in soft-delete.
      purge_soft_delete_on_destroy = true
    }
  }
  subscription_id = local.shared.subscription_id
  tenant_id       = local.shared.tenant_id
  # The canary blob is written with the account key: this account keeps shared keys on, because
  # key-based data access (Fenrir D-01) is part of what the run should log.
  storage_use_azuread             = false
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.Automation",
    "Microsoft.Compute",
    "Microsoft.ContainerInstance",
    "Microsoft.ContainerRegistry",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.Logic",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.Security",
    "Microsoft.Storage",
    "Microsoft.Web",
  ]
}
