output "workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = azurerm_log_analytics_workspace.this.id
}

output "workspace_customer_id" {
  description = "Workspace GUID, used by tests/validate_alert.py and az monitor log-analytics query."
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

output "deployed_rules" {
  description = "Rule IDs deployed as scheduled analytics rules."
  value       = sort(keys(local.rules))
}

output "skipped_rules" {
  description = "Rule IDs present in detections/ but not deployed (not deployable here, disabled, or deploy_rules = false)."
  value       = sort(setsubtract(keys(local.rules_all), keys(local.rules)))
}
