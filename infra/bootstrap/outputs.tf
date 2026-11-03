locals {
  shared = {
    tenant_id                    = var.tenant_id
    subscription_id              = var.subscription_id
    location                     = var.location
    state_resource_group         = azurerm_resource_group.state.name
    state_storage_account        = azurerm_storage_account.state.name
    state_container              = azurerm_storage_container.state.name
    sentinel_resource_group      = azurerm_resource_group.sentinel.name
    lab_resource_group           = azurerm_resource_group.lab.name
    deploy_client_id             = azuread_application.deploy.client_id
    deploy_principal_object_id   = azuread_service_principal.deploy.object_id
    attacker_client_id           = azuread_application.attacker.client_id
    attacker_principal_object_id = azuread_service_principal.attacker.object_id
    replay_environment           = var.replay_environment
  }
}

# Non-secret identifiers shared with the other stacks and the workflows. Committed to git:
# client IDs, object IDs and resource names are not credentials (OIDC needs no secret).
resource "local_file" "shared" {
  filename        = "${path.module}/../shared/bootstrap.json"
  content         = "${jsonencode(local.shared)}\n"
  file_permission = "0644"
}

resource "local_file" "backend" {
  filename        = "${path.module}/../shared/backend.hcl"
  file_permission = "0644"
  content         = <<-EOT
    resource_group_name  = "${azurerm_resource_group.state.name}"
    storage_account_name = "${azurerm_storage_account.state.name}"
    container_name       = "${azurerm_storage_container.state.name}"
    use_azuread_auth     = true
    tenant_id            = "${var.tenant_id}"
    subscription_id      = "${var.subscription_id}"
  EOT
}

output "shared" {
  description = "Identifiers for GitHub repository variables (AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, AZURE_DEPLOY_CLIENT_ID, AZURE_ATTACKER_CLIENT_ID)."
  value       = local.shared
}
