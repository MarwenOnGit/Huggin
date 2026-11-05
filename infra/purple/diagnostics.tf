# "Log everything": every resource sends every log category it has (the allLogs category
# group) to the Huginn workspace. The subscription Activity log already goes there from
# infra/sentinel; Entra ID sign-in and Graph activity logs are switched on there too
# (enable_entra_logs, needs P1/P2). The VM's host logs go through the DCR in vm.tf.
#
# Not covered, and why (docs/PURPLE-TEAM.md):
# - Container group: exec sessions have no resource log category, and container logs need a
#   workspace shared key, which law-huginn disables. X-14 is seen in AzureActivity only.
# - VM, NIC, managed identity: no resource log categories.
# - Metrics: no detection value, so not collected.

locals {
  diagnostic_targets = merge(
    {
      logic_app  = azurerm_logic_app_workflow.target.id
      automation = azurerm_automation_account.target.id
      key_vault  = azurerm_key_vault.target.id
      # Storage logs are per service, not per account.
      blob  = "${azurerm_storage_account.target.id}/blobServices/default"
      file  = "${azurerm_storage_account.target.id}/fileServices/default"
      queue = "${azurerm_storage_account.target.id}/queueServices/default"
      table = "${azurerm_storage_account.target.id}/tableServices/default"
    },
    var.enable_webapp ? { web_app = azurerm_linux_web_app.target[0].id } : {},
    var.enable_acr ? { registry = azurerm_container_registry.target[0].id } : {},
  )
}

resource "azurerm_monitor_diagnostic_setting" "all_logs" {
  for_each                   = local.diagnostic_targets
  name                       = "huginn-purple-all-logs"
  target_resource_id         = each.value
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.huginn.id

  enabled_log {
    category_group = "allLogs"
  }
}
