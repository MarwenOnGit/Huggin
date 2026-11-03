# Two GitHub Actions identities, both secretless (OIDC federated credentials only).
#
# 1. huginn-github-deploy: runs Terraform for the sentinel and lab stacks. It is listed in the
#    HuginnTrustedAutomation watchlist so its Terraform refreshes (listKeys, listCallbackUrl,
#    publishing credentials, ACR credentials) never fire rules.
# 2. huginn-lab-attacker: performs the benign replays. Contributor on the lab resource group
#    only. It is NEVER in the watchlist, so its actions must raise alerts.

# --- Deploy identity -------------------------------------------------------------------------

resource "azuread_application" "deploy" {
  display_name     = "huginn-github-deploy"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azurerm_client_config.current.object_id]
  notes            = "Huginn: GitHub Actions Terraform deployments (OIDC, no secrets)."
}

resource "azuread_service_principal" "deploy" {
  client_id = azuread_application.deploy.client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

resource "azuread_application_federated_identity_credential" "deploy_main" {
  #checkov:skip=CKV_AZURE_249:False positive: checkov expects repo:owner/repo, but GitHub ID-based subjects are repo:owner@id/repo@id; the subject pins one immutable repo and one branch or environment, no wildcard (ADR 0003, 0004)
  application_id = azuread_application.deploy.id
  display_name   = "github-main"
  description    = "Workflows on the main branch of ${var.github_repository}."
  issuer         = local.oidc_issuer
  audiences      = local.oidc_audience
  subject        = "${local.github_subject_prefix}:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "deploy_sentinel_rg" {
  scope                = azurerm_resource_group.sentinel.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deploy.object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deploy_lab_rg" {
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.deploy.object_id
  principal_type       = "ServicePrincipal"
}

# Needed only for the subscription Activity log diagnostic setting.
resource "azurerm_role_assignment" "deploy_monitoring" {
  scope                = local.subscription
  role_definition_name = "Monitoring Contributor"
  principal_id         = azuread_service_principal.deploy.object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deploy_state" {
  scope                = azurerm_storage_container.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.deploy.object_id
  principal_type       = "ServicePrincipal"
}

# --- Lab attacker identity -------------------------------------------------------------------

resource "azuread_application" "attacker" {
  display_name     = "huginn-lab-attacker"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azurerm_client_config.current.object_id]
  notes            = "Huginn: benign replays of Fenrir-shaped actions against huginn-lab-rg only."
}

resource "azuread_service_principal" "attacker" {
  client_id = azuread_application.attacker.client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

resource "azuread_application_federated_identity_credential" "attacker_replay" {
  #checkov:skip=CKV_AZURE_249:False positive: checkov expects repo:owner/repo, but GitHub ID-based subjects are repo:owner@id/repo@id; the subject pins one immutable repo and one branch or environment, no wildcard (ADR 0003, 0004)
  application_id = azuread_application.attacker.id
  display_name   = "github-env-${var.replay_environment}"
  description    = "Only jobs that run in the ${var.replay_environment} environment of ${var.github_repository}."
  issuer         = local.oidc_issuer
  audiences      = local.oidc_audience
  subject        = "${local.github_subject_prefix}:environment:${var.replay_environment}"
}

resource "azurerm_role_assignment" "attacker_lab_rg" {
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.attacker.object_id
  principal_type       = "ServicePrincipal"
}
