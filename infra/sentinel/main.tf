locals {
  shared_path = "${path.module}/../shared/bootstrap.json"
  # try(): lets `terraform validate` run in CI before bootstrap has produced the file.
  shared = try(jsondecode(file(local.shared_path)), {
    tenant_id                  = "00000000-0000-0000-0000-000000000000"
    subscription_id            = "00000000-0000-0000-0000-000000000000"
    location                   = "francecentral"
    sentinel_resource_group    = "huginn-sentinel-rg"
    lab_resource_group         = "huginn-lab-rg"
    state_resource_group       = "huginn-tfstate-rg"
    deploy_principal_object_id = "00000000-0000-0000-0000-000000000000"
  })
  subscription = "/subscriptions/${local.shared.subscription_id}"
  tags = {
    project    = "huginn"
    managed-by = "terraform"
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

data "azurerm_resource_group" "sentinel" {
  name = local.shared.sentinel_resource_group
}

resource "azurerm_log_analytics_workspace" "this" {
  name                         = "law-huginn"
  location                     = data.azurerm_resource_group.sentinel.location
  resource_group_name          = data.azurerm_resource_group.sentinel.name
  sku                          = "PerGB2018"
  retention_in_days            = var.retention_in_days
  daily_quota_gb               = var.daily_quota_gb
  local_authentication_enabled = false
  tags                         = local.tags

  depends_on = [terraform_data.bootstrap_present]
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "this" {
  workspace_id = azurerm_log_analytics_workspace.this.id
}

# Azure Activity connector: the subscription Activity log, sent to the workspace.
# AzureActivity ingestion is free in Log Analytics and Sentinel.
resource "azurerm_monitor_diagnostic_setting" "activity" {
  name                       = "huginn-activity-to-law"
  target_resource_id         = local.subscription
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset(var.activity_log_categories)
    content {
      category = enabled_log.value
    }
  }
}

# Entra ID logs (identity tier). Needs P1/P2; off by default. Only a person with Global or
# Security Administrator can apply this, so CI never sets enable_entra_logs.
resource "azurerm_monitor_aad_diagnostic_setting" "entra" {
  count                      = var.enable_entra_logs ? 1 : 0
  name                       = "huginn-entra-to-law"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset([
      "SignInLogs",
      "NonInteractiveUserSignInLogs",
      "ManagedIdentitySignInLogs",
      "MicrosoftGraphActivityLogs",
    ])
    content {
      category = enabled_log.value
    }
  }
}
