# Bootstrap: run once, locally, by a Global Administrator / subscription Owner.
# Creates the resource groups, the remote state storage and the two GitHub identities.
# CI never applies this stack, so CI never needs rights to create apps or role assignments.

data "azurerm_client_config" "current" {}

locals {
  # Deterministic, globally unique-enough suffix so other stacks can derive names.
  suffix        = substr(sha1(var.subscription_id), 0, 10)
  state_account = "sthuginntf${local.suffix}"
  subscription  = "/subscriptions/${var.subscription_id}"
  oidc_issuer   = "https://token.actions.githubusercontent.com"
  oidc_audience = ["api://AzureADTokenExchange"]
}

# Resource groups. Created here so role assignments can be scoped to them before the
# sentinel and lab stacks exist. Empty resource groups cost nothing.
resource "azurerm_resource_group" "state" {
  name     = "huginn-tfstate-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "sentinel" {
  name     = "huginn-sentinel-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "lab" {
  name     = "huginn-lab-rg"
  location = var.location
  tags     = var.tags
}

# Remote state for the sentinel and lab stacks. Entra ID auth only (no shared keys).
resource "azurerm_storage_account" "state" {
  #checkov:skip=CKV_AZURE_59:Public endpoint needed by GitHub-hosted runners; shared keys are disabled, Entra ID auth only (ADR 0004)
  #checkov:skip=CKV2_AZURE_33:Private endpoint costs per hour and runners could not reach it (ADR 0004)
  #checkov:skip=CKV_AZURE_206:LRS on a student budget; versioning and soft delete protect the state (ADR 0004)
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed keys; a Key Vault CMK adds cost and no value for state files (ADR 0004)
  #checkov:skip=CKV_AZURE_33:No queues are used (ADR 0004)
  name                             = local.state_account
  resource_group_name              = azurerm_resource_group.state.name
  location                         = var.location
  account_tier                     = "Standard"
  account_replication_type         = "LRS"
  account_kind                     = "StorageV2"
  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  tags                             = var.tags

  lifecycle {
    prevent_destroy = true # holds every Huginn state file; remove this line on purpose to tear down
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "state" {
  #checkov:skip=CKV2_AZURE_21:Blob read logging is billed per GB; state access is visible in AzureActivity role assignments and Entra sign-ins (ADR 0004)
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

# The person running bootstrap needs data-plane access to use the remote backend locally.
resource "azurerm_role_assignment" "operator_state" {
  scope                = azurerm_storage_container.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
