# Resource IDs only. No secrets: the callback URL, keys and credentials are never output.

output "resource_group" {
  description = "Lab resource group name."
  value       = data.azurerm_resource_group.lab.name
}

output "logic_app_id" {
  description = "X-13 target workflow."
  value       = azurerm_logic_app_workflow.lab.id
}

output "logic_app_trigger_name" {
  description = "X-13 target trigger name."
  value       = azurerm_logic_app_trigger_http_request.lab.name
}

output "storage_account_id" {
  description = "Always-on P-12 target (evidence and demo; CI uses a fresh account per run)."
  value       = azurerm_storage_account.lab.id
}

output "user_assigned_identity_id" {
  description = "Identity attached to the lab hosts."
  value       = azurerm_user_assigned_identity.lab.id
}

output "vm_id" {
  description = "X-08 target, if enabled."
  value       = try(azurerm_linux_virtual_machine.lab[0].id, null)
}

output "web_app_id" {
  description = "X-10 target, if enabled."
  value       = try(azurerm_linux_web_app.lab[0].id, null)
}

output "container_group_id" {
  description = "X-14 target, if enabled."
  value       = try(azurerm_container_group.lab[0].id, null)
}

output "container_registry_id" {
  description = "P-13 target, if enabled."
  value       = try(azurerm_container_registry.lab[0].id, null)
}
