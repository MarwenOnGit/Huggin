# Fenrir-shaped target environment: only what the core replays need.
# Always-on resources cost (near) nothing while idle.

locals {
  shared_path = "${path.module}/../shared/bootstrap.json"
  shared = try(jsondecode(file(local.shared_path)), {
    tenant_id          = "00000000-0000-0000-0000-000000000000"
    subscription_id    = "00000000-0000-0000-0000-000000000000"
    lab_resource_group = "huginn-lab-rg"
  })
  suffix = substr(sha1("${local.shared.subscription_id}-lab"), 0, 8)
  tags = {
    project    = "huginn"
    managed-by = "terraform"
    purpose    = "huginn-lab"
  }
}

resource "terraform_data" "bootstrap_present" {
  lifecycle {
    precondition {
      condition     = fileexists(local.shared_path)
      error_message = "infra/shared/bootstrap.json is missing. Apply infra/bootstrap first."
    }
  }
}

data "azurerm_resource_group" "lab" {
  name       = local.shared.lab_resource_group
  depends_on = [terraform_data.bootstrap_present]
}

# User-assigned identity attached to the lab hosts, the shape Fenrir looks for.
resource "azurerm_user_assigned_identity" "lab" {
  name                = "id-huginn-lab"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags
}

# X-13 target: Logic App (Consumption) with an HTTP Request trigger. No runs, so no cost.
# Note: the azurerm provider reads the trigger callback URL on every refresh, as the deployment
# principal. That principal is in the HuginnTrustedAutomation watchlist for this scope.
resource "azurerm_logic_app_workflow" "lab" {
  name                = "logic-huginn-lab"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.lab.id]
  }
}

resource "azurerm_logic_app_trigger_http_request" "lab" {
  name         = "manual"
  logic_app_id = azurerm_logic_app_workflow.lab.id
  schema       = jsonencode({})
}

# P-12 target (always-on account for evidence and the demo). CI replays create a FRESH account
# per run instead, to avoid the 14-day "known pair" baseline trap (docs/TESTING.md).
# tflint-ignore: azurerm_resources_missing_prevent_destroy # empty lab target, must go with make destroy
resource "azurerm_storage_account" "lab" {
  #checkov:skip=CKV_AZURE_59:False positive: public_network_access = "Disabled" (azurerm 5.x name) is not recognised by checkov 3.4.3
  #checkov:skip=CKV_AZURE_43:False positive: the name is interpolated and is valid (3-24 lower-case alphanumerics)
  #checkov:skip=CKV2_AZURE_33:Lab target with public network access disabled; a private endpoint costs per hour (ADR 0004)
  #checkov:skip=CKV_AZURE_206:LRS on a student budget; the account holds no data (ADR 0004)
  #checkov:skip=CKV2_AZURE_1:Holds no data; CMK adds cost (ADR 0004)
  #checkov:skip=CKV_AZURE_33:No queues are used (ADR 0004)
  name                             = "sthuginnlab${local.suffix}"
  resource_group_name              = data.azurerm_resource_group.lab.name
  location                         = data.azurerm_resource_group.lab.location
  account_tier                     = "Standard"
  account_replication_type         = "LRS"
  account_kind                     = "StorageV2"
  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  # listKeys (P-12) is a control-plane action, so the data plane can stay closed.
  public_network_access = "Disabled"
  tags                  = local.tags

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }
}
