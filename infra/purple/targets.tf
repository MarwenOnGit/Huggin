# Every other resource type Fenrir acts on. Each one holds a canary (see local.canary): a
# random, searchable value placed where a real secret would be, so the run shows which logs,
# if any, a stolen secret ends up in.

# --- X-10 / X-11: App Service publishing credentials and Kudu --------------------------------

resource "azurerm_service_plan" "target" {
  #checkov:skip=CKV_AZURE_211:Free tier on purpose: disposable purple-team target (ADR 0008)
  #checkov:skip=CKV_AZURE_212:Free tier has one instance (ADR 0008)
  #checkov:skip=CKV_AZURE_225:Zone redundancy needs Premium (ADR 0008)
  count               = var.enable_webapp ? 1 : 0
  name                = "asp-huginn-purple"
  location            = azurerm_resource_group.purple.location
  resource_group_name = azurerm_resource_group.purple.name
  os_type             = "Linux"
  sku_name            = var.webapp_sku
  tags                = local.tags
}

# tflint-ignore: azurerm_app_service_missing_auto_heal_setting # no application to heal; disposable target (ADR 0008)
resource "azurerm_linux_web_app" "target" {
  #checkov:skip=CKV_AZURE_214:Always On is not available on the Free tier (ADR 0008)
  #checkov:skip=CKV_AZURE_222:Public site on purpose: Kudu (X-11) is reached from the operator's machine (ADR 0008)
  #checkov:skip=CKV_AZURE_213:No application, so no health check endpoint (ADR 0008)
  #checkov:skip=CKV_AZURE_88:No content to store (ADR 0008)
  #checkov:skip=CKV_AZURE_13:No application to protect; X-10 and X-11 target the control plane and Kudu (ADR 0008)
  #checkov:skip=CKV_AZURE_17:No application to protect (ADR 0008)
  count               = var.enable_webapp ? 1 : 0
  name                = "app-huginn-purple-${local.suffix}"
  location            = azurerm_resource_group.purple.location
  resource_group_name = azurerm_resource_group.purple.name
  service_plan_id     = azurerm_service_plan.target[0].id
  https_only          = true
  # SCM basic auth on: the precondition Fenrir checks (E-19) before X-10 and X-11.
  webdeploy_publish_basic_authentication_enabled = true
  ftp_publish_basic_authentication_enabled       = false
  tags                                           = local.tags

  # A secret in an app setting, the way real apps leak them. Readable through Kudu (X-11).
  app_settings = {
    HUGINN_CANARY = local.canary
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    http_logs {
      file_system {
        retention_in_days = 1
        retention_in_mb   = 25
      }
    }
  }

  site_config {
    always_on           = false # not available on F1
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"
    http2_enabled       = true
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.target.id]
  }
}

# --- X-12 / X-13: Logic App callback URL ----------------------------------------------------
# Note: the azurerm provider reads the callback URL on every refresh, as the operator. Those
# rows are the operator's, not the attacker's; the capture filters by the attacker's identity.

resource "azurerm_logic_app_workflow" "target" {
  name                = "logic-huginn-purple"
  location            = azurerm_resource_group.purple.location
  resource_group_name = azurerm_resource_group.purple.name
  tags                = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.target.id]
  }
}

resource "azurerm_logic_app_trigger_http_request" "target" {
  name         = "manual"
  logic_app_id = azurerm_logic_app_workflow.target.id
  schema       = jsonencode({})
}

# --- X-14: Container Instances exec ---------------------------------------------------------

resource "azurerm_container_group" "target" {
  #checkov:skip=CKV_AZURE_98:No IP address at all (ip_address_type = None); VNet injection adds a subnet and delegation for a disposable target (ADR 0008)
  count               = var.enable_aci ? 1 : 0
  name                = "aci-huginn-purple"
  location            = azurerm_resource_group.purple.location
  resource_group_name = azurerm_resource_group.purple.name
  os_type             = "Linux"
  ip_address_type     = "None"
  restart_policy      = "Never"
  tags                = local.tags

  container {
    name     = "idle"
    image    = "mcr.microsoft.com/azurelinux/busybox:1.36"
    cpu      = 0.5
    memory   = 0.5
    commands = ["/bin/sh", "-c", "sleep 14400"]

    # Visible to anyone who execs into the container (X-14), hidden in the control plane.
    secure_environment_variables = {
      HUGINN_CANARY = local.canary
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.target.id]
  }
}

# --- X-15 to X-18: Automation Account (runbook source, variables, credentials) ---------------

resource "azurerm_automation_account" "target" {
  #checkov:skip=CKV2_AZURE_24:Public network on purpose: the tools reach it from the operator's machine (ADR 0008)
  name                = "aa-huginn-purple"
  location            = azurerm_resource_group.purple.location
  resource_group_name = azurerm_resource_group.purple.name
  sku_name            = "Basic"
  tags                = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.target.id]
  }
}

# Never runs. Its source holds a hard-coded canary, which X-16 downloads.
resource "azurerm_automation_runbook" "target" {
  name                    = "Get-HuginnInventory"
  location                = azurerm_resource_group.purple.location
  resource_group_name     = azurerm_resource_group.purple.name
  automation_account_name = azurerm_automation_account.target.name
  runbook_type            = "PowerShell"
  log_verbose             = true
  log_progress            = true
  description             = "Huggin purple-team canary runbook. Never scheduled, never run."
  tags                    = local.tags

  content = <<-EOT
    # Huggin purple-team canary runbook. Never scheduled, never run.
    $apiToken = '${local.canary}'
    Write-Output 'idle'
  EOT
}

# Unencrypted on purpose: X-17 lists variables, and an unencrypted value is what an operator
# would actually get.
resource "azurerm_automation_variable_string" "canary" {
  #checkov:skip=CKV_AZURE_73:Unencrypted canary on purpose: it is what X-17 reads (ADR 0008)
  name                    = "HuginnCanary"
  resource_group_name     = azurerm_resource_group.purple.name
  automation_account_name = azurerm_automation_account.target.name
  value                   = local.canary
  encrypted               = false
}

resource "azurerm_automation_credential" "canary" {
  name                    = "huginn-svc"
  resource_group_name     = azurerm_resource_group.purple.name
  automation_account_name = azurerm_automation_account.target.name
  username                = "huginn-svc"
  password                = local.canary
}

# --- P-12 / D-01: storage keys and blob data -------------------------------------------------

# tflint-ignore: azurerm_resources_missing_prevent_destroy # disposable purple-team target, must go with make purple-destroy (ADR 0008)
resource "azurerm_storage_account" "target" {
  #checkov:skip=CKV_AZURE_59:Public network on purpose: D-01 reads blobs from the operator's machine (ADR 0008)
  #checkov:skip=CKV2_AZURE_40:Shared keys on purpose: they are what P-12 lists and D-01 uses (ADR 0008)
  #checkov:skip=CKV_AZURE_43:False positive: the name is interpolated and is valid (3-24 lower-case alphanumerics)
  #checkov:skip=CKV2_AZURE_33:Disposable target; a private endpoint costs per hour and would block D-01 (ADR 0008)
  #checkov:skip=CKV_AZURE_206:LRS: the account holds one canary blob (ADR 0008)
  #checkov:skip=CKV2_AZURE_1:Holds one canary blob; CMK adds cost (ADR 0008)
  #checkov:skip=CKV_AZURE_33:Queue logging comes from the diagnostic setting in diagnostics.tf (ADR 0008)
  #checkov:skip=CKV2_AZURE_21:Blob logging comes from the diagnostic setting in diagnostics.tf (ADR 0008)
  name                             = "sthgpurple${local.suffix}"
  resource_group_name              = azurerm_resource_group.purple.name
  location                         = azurerm_resource_group.purple.location
  account_tier                     = "Standard"
  account_replication_type         = "LRS"
  account_kind                     = "StorageV2"
  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  shared_access_key_enabled        = true
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  local_user_enabled               = false
  public_network_access            = "Enabled"
  tags                             = local.tags

  sas_policy {
    expiration_period = "00.01:00:00"
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }
}

# tflint-ignore: azurerm_resources_missing_prevent_destroy # disposable purple-team target, must go with make purple-destroy (ADR 0008)
resource "azurerm_storage_container" "canary" {
  #checkov:skip=CKV2_AZURE_21:Blob logging comes from the diagnostic setting in diagnostics.tf (ADR 0008)
  name                  = "huginn-canary"
  storage_account_id    = azurerm_storage_account.target.id
  container_access_type = "private"
}

# tflint-ignore: azurerm_resources_missing_prevent_destroy # disposable purple-team target, must go with make purple-destroy (ADR 0008)
resource "azurerm_storage_blob" "canary" {
  name                 = "credentials.txt"
  storage_container_id = azurerm_storage_container.canary.id
  type                 = "Block"
  source_content       = "service_password=${local.canary}\n"
}

# --- P-13 / D-03: registry admin credentials -------------------------------------------------

resource "azurerm_container_registry" "target" {
  #checkov:skip=CKV_AZURE_137:The admin user IS the P-13 target (ADR 0008)
  #checkov:skip=CKV_AZURE_139:Basic SKU cannot disable public networking (ADR 0008)
  #checkov:skip=CKV_AZURE_163:Empty registry; scanning needs Defender for Containers (ADR 0008)
  #checkov:skip=CKV_AZURE_164:Empty registry; content trust needs Premium (ADR 0008)
  #checkov:skip=CKV_AZURE_165:Geo-replication needs Premium (ADR 0008)
  #checkov:skip=CKV_AZURE_166:Quarantine needs Premium (ADR 0008)
  #checkov:skip=CKV_AZURE_167:Retention policy needs Premium (ADR 0008)
  #checkov:skip=CKV_AZURE_233:Zone redundancy needs Premium (ADR 0008)
  #checkov:skip=CKV_AZURE_237:Dedicated data endpoints need Premium (ADR 0008)
  count               = var.enable_acr ? 1 : 0
  name                = "acrhgpurple${local.suffix}"
  location            = azurerm_resource_group.purple.location
  resource_group_name = azurerm_resource_group.purple.name
  sku                 = "Basic"
  admin_enabled       = true
  tags                = local.tags
}

# --- Key Vault (E-27 reads it; other tools go further) --------------------------------------

# tflint-ignore: azurerm_resources_missing_prevent_destroy # disposable purple-team target, must go with make purple-destroy (ADR 0008)
resource "azurerm_key_vault" "target" {
  #checkov:skip=CKV_AZURE_109:Public network on purpose: Terraform and the tools run from the operator's machine (ADR 0008)
  #checkov:skip=CKV_AZURE_189:Public network on purpose (ADR 0008)
  #checkov:skip=CKV_AZURE_42:Recoverable means purge protection; see CKV_AZURE_110 (ADR 0008)
  #checkov:skip=CKV_AZURE_110:Purge protection would keep the disposable vault for 7+ days after destroy (ADR 0008)
  #checkov:skip=CKV2_AZURE_32:Disposable target; a private endpoint costs per hour (ADR 0008)
  name                       = "kv-hgpurple-${local.suffix}"
  location                   = azurerm_resource_group.purple.location
  resource_group_name        = azurerm_resource_group.purple.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  # Access policies take effect at once; RBAC data roles can take minutes to propagate.
  rbac_authorization_enabled = false
  tags                       = local.tags

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  access_policy {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    object_id          = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
  }

  # The managed identity can read secrets, as many real workloads can.
  access_policy {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    object_id          = azurerm_user_assigned_identity.target.principal_id
    secret_permissions = ["Get", "List"]
  }
}

# tflint-ignore: azurerm_resources_missing_prevent_destroy # disposable purple-team target, must go with make purple-destroy (ADR 0008)
resource "azurerm_key_vault_secret" "canary" {
  name            = "huginn-canary"
  value           = local.canary
  key_vault_id    = azurerm_key_vault.target.id
  content_type    = "text/plain"
  expiration_date = var.canary_expires_on
  tags            = local.tags
}
