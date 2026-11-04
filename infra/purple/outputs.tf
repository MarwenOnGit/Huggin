# IDs and names only. No secrets: the canary value, keys, the SSH key and the callback URL are
# never output. The capture script searches for the canary PREFIX, which is not secret.

output "resource_group" {
  description = "Purple resource group."
  value       = azurerm_resource_group.purple.name
}

output "canary_prefix" {
  description = "Prefix of every canary value. A log row that contains it carries a secret."
  value       = local.canary_prefix
}

output "identity_principal_id" {
  description = "Object ID of the user-assigned identity Fenrir extracts tokens for."
  value       = azurerm_user_assigned_identity.target.principal_id
}

output "identity_client_id" {
  description = "Client ID of the user-assigned identity."
  value       = azurerm_user_assigned_identity.target.client_id
}

output "identity_resource_id" {
  description = "Resource ID of the user-assigned identity (xms_mirid in its tokens)."
  value       = azurerm_user_assigned_identity.target.id
}

output "attacker_object_id" {
  description = "The attacker user given Contributor on the resource group, if any."
  value       = var.attacker_object_id
}

output "vm_principal_id" {
  description = "Object ID of the VM's system-assigned identity (used by the Azure Monitor Agent)."
  value       = try(azurerm_linux_virtual_machine.target[0].identity[0].principal_id, null)
}

output "workspace_customer_id" {
  description = "Workspace the run is logged to."
  value       = data.azurerm_log_analytics_workspace.huginn.workspace_id
}
