# Purple-team environment: every resource type Fenrir targets, each with every log category it
# can emit sent to the Huginn workspace. Disposable: apply for one run, destroy right after.
#
# Separate from infra/lab on purpose. infra/lab holds the benign replay targets that CI acts on
# every night. This stack is for a real Fenrir run by a person (docs/PURPLE-TEAM.md), so it gets
# its own resource group, its own identity and canary secrets, and CI never acts on it.

locals {
  shared_path = "${path.module}/../shared/bootstrap.json"
  shared = try(jsondecode(file(local.shared_path)), {
    tenant_id               = "00000000-0000-0000-0000-000000000000"
    subscription_id         = "00000000-0000-0000-0000-000000000000"
    location                = "francecentral"
    sentinel_resource_group = "huginn-sentinel-rg"
  })
  location = local.shared.location
  suffix   = random_string.suffix.result
  # Searchable in every table: the capture script flags any row that contains this prefix,
  # because a canary in a log means a secret reached the log.
  canary_prefix = "HUGINN-CANARY-"
  canary        = "${local.canary_prefix}${random_string.canary.result}"
  tags = {
    project        = "huginn"
    managed-by     = "terraform"
    purpose        = "huginn-purple"
    huginn-purple  = var.run_label
    do-not-replay  = "true"
    owner-contact  = "purple-team operator"
    teardown-after = "one run"
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

# Fresh names per environment: a destroyed Key Vault or registry name is not reused.
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "random_string" "canary" {
  length  = 20
  upper   = false
  special = false
}

data "azurerm_client_config" "current" {}

# The workspace from infra/sentinel. Every diagnostic setting and the host DCR send there.
data "azurerm_log_analytics_workspace" "huginn" {
  name                = "law-huginn"
  resource_group_name = local.shared.sentinel_resource_group
  depends_on          = [terraform_data.bootstrap_present]
}

resource "azurerm_resource_group" "purple" {
  name     = "huginn-purple-rg"
  location = local.location
  tags     = local.tags
}

# --- Identities and access ------------------------------------------------------------------

# User-assigned identity on every host, the shape Fenrir looks for and extracts tokens for.
resource "azurerm_user_assigned_identity" "target" {
  name                = "id-huginn-purple"
  location            = azurerm_resource_group.purple.location
  resource_group_name = azurerm_resource_group.purple.name
  tags                = local.tags
}

# What the identity can do once Fenrir holds its token: read the resource group (P-01 to P-11),
# list the storage keys (P-12), read blobs with OAuth (D-01) and list the registry
# credentials (P-13).
resource "azurerm_role_assignment" "mi_reader" {
  scope                = azurerm_resource_group.purple.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.target.principal_id
}

resource "azurerm_role_assignment" "mi_storage_keys" {
  scope                = azurerm_storage_account.target.id
  role_definition_name = "Storage Account Key Operator Service Role"
  principal_id         = azurerm_user_assigned_identity.target.principal_id
}

resource "azurerm_role_assignment" "mi_blob_reader" {
  scope                = azurerm_storage_account.target.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.target.principal_id
}

resource "azurerm_role_assignment" "mi_acr" {
  count                = var.enable_acr ? 1 : 0
  scope                = azurerm_container_registry.target[0].id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.target.principal_id
}

# The attacker: a dedicated low-privilege user, Contributor on this resource group only.
resource "azurerm_role_assignment" "attacker" {
  count                = var.attacker_object_id == "" ? 0 : 1
  scope                = azurerm_resource_group.purple.id
  role_definition_name = "Contributor"
  principal_id         = var.attacker_object_id
}

# --- Defender for Resource Manager (opt-in, subscription-wide) ------------------------------

resource "azurerm_security_center_subscription_pricing" "arm" {
  count         = var.enable_defender_arm ? 1 : 0
  tier          = "Standard"
  resource_type = "Arm"
}
