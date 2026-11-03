# Opt-in resources. Created for one replay run, removed right after.

# --- X-08: VM Run Command -------------------------------------------------------------------

resource "azurerm_virtual_network" "lab" {
  count               = var.enable_vm ? 1 : 0
  name                = "vnet-huginn-lab"
  location            = coalesce(var.vm_location, data.azurerm_resource_group.lab.location)
  resource_group_name = data.azurerm_resource_group.lab.name
  address_space       = ["10.42.0.0/24"]
  tags                = local.tags
}

resource "azurerm_subnet" "lab" {
  count                = var.enable_vm ? 1 : 0
  name                 = "snet-vm"
  resource_group_name  = data.azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab[0].name
  address_prefixes     = ["10.42.0.0/26"]
}

# No inbound rules: Run Command goes through the VM agent, not the network.
resource "azurerm_network_security_group" "lab" {
  count               = var.enable_vm ? 1 : 0
  name                = "nsg-huginn-lab"
  location            = coalesce(var.vm_location, data.azurerm_resource_group.lab.location)
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "lab" {
  count                     = var.enable_vm ? 1 : 0
  subnet_id                 = azurerm_subnet.lab[0].id
  network_security_group_id = azurerm_network_security_group.lab[0].id
}

resource "azurerm_network_interface" "lab" {
  count               = var.enable_vm ? 1 : 0
  name                = "nic-huginn-lab"
  location            = coalesce(var.vm_location, data.azurerm_resource_group.lab.location)
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lab[0].id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "lab" {
  #checkov:skip=CKV_AZURE_50:Run Command needs the VM agent and extension operations; this is the X-08 target (ADR 0004)
  count                           = var.enable_vm ? 1 : 0
  name                            = "vm-huginn-lab"
  location                        = coalesce(var.vm_location, data.azurerm_resource_group.lab.location)
  resource_group_name             = data.azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "huginn"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.lab[0].id]
  allow_extension_operations      = true
  disk_controller_type            = "NVMe"
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  tags                            = local.tags

  admin_ssh_key {
    username   = "huginn"
    public_key = var.vm_admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.lab.id]
  }

  lifecycle {
    precondition {
      condition     = var.vm_admin_ssh_public_key != null
      error_message = "enable_vm needs vm_admin_ssh_public_key (a throwaway key generated for this run)."
    }
  }
}

# --- X-10: App Service publishing credentials -----------------------------------------------

resource "azurerm_service_plan" "lab" {
  #checkov:skip=CKV_AZURE_211:Free tier on purpose: lab target that lives for one replay run (ADR 0004)
  #checkov:skip=CKV_AZURE_212:Free tier has one instance (ADR 0004)
  #checkov:skip=CKV_AZURE_225:Zone redundancy needs Premium (ADR 0004)
  count               = var.enable_appservice ? 1 : 0
  name                = "asp-huginn-lab"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  os_type             = "Linux"
  sku_name            = "F1"
  tags                = local.tags
}

resource "azurerm_linux_web_app" "lab" {
  #checkov:skip=CKV_AZURE_214:Always On is not available on the Free tier (ADR 0004)
  #checkov:skip=CKV_AZURE_222:Public site; it serves the default page only and lives for one run (ADR 0004)
  #checkov:skip=CKV_AZURE_213:No application, so no health check endpoint (ADR 0004)
  #checkov:skip=CKV_AZURE_88:No content to store (ADR 0004)
  #checkov:skip=CKV_AZURE_13:No application to protect; X-10 targets the control plane (ADR 0004)
  #checkov:skip=CKV_AZURE_17:No application to protect (ADR 0004)
  count               = var.enable_appservice ? 1 : 0
  name                = "app-huginn-lab-${local.suffix}"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  service_plan_id     = azurerm_service_plan.lab[0].id
  https_only          = true
  # SCM basic auth on: this is the precondition Fenrir checks before X-10 (E-19).
  webdeploy_publish_basic_authentication_enabled = true
  ftp_publish_basic_authentication_enabled       = false
  tags                                           = local.tags

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
    identity_ids = [azurerm_user_assigned_identity.lab.id]
  }
}

# --- X-14: Container Instances exec ---------------------------------------------------------

resource "azurerm_container_group" "lab" {
  #checkov:skip=CKV_AZURE_98:No IP address at all (ip_address_type = None); VNet injection adds a subnet and delegation for a one-run target (ADR 0004)
  count               = var.enable_aci ? 1 : 0
  name                = "aci-huginn-lab"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  os_type             = "Linux"
  ip_address_type     = "None"
  restart_policy      = "Never"
  tags                = local.tags

  container {
    name     = "idle"
    image    = "mcr.microsoft.com/azurelinux/busybox:1.36"
    cpu      = 0.5
    memory   = 0.5
    commands = ["/bin/sh", "-c", "sleep 7200"]
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.lab.id]
  }
}

# --- P-13: ACR admin credentials ------------------------------------------------------------

resource "azurerm_container_registry" "lab" {
  #checkov:skip=CKV_AZURE_137:The admin user IS the P-13 target; registry is empty and deleted after each run (ADR 0004)
  #checkov:skip=CKV_AZURE_139:Basic SKU cannot disable public networking (ADR 0004)
  #checkov:skip=CKV_AZURE_163:Empty registry; scanning needs Defender for Containers (ADR 0004)
  #checkov:skip=CKV_AZURE_164:Empty registry; content trust needs Premium (ADR 0004)
  #checkov:skip=CKV_AZURE_165:Geo-replication needs Premium (ADR 0004)
  #checkov:skip=CKV_AZURE_166:Quarantine needs Premium (ADR 0004)
  #checkov:skip=CKV_AZURE_167:Retention policy needs Premium (ADR 0004)
  #checkov:skip=CKV_AZURE_233:Zone redundancy needs Premium (ADR 0004)
  #checkov:skip=CKV_AZURE_237:Dedicated data endpoints need Premium (ADR 0004)
  count               = var.enable_acr ? 1 : 0
  name                = "acrhuginnlab${local.suffix}"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  sku                 = "Basic"
  # The admin user is the target of P-13 (listCredentials). Lab only, deleted after each run.
  admin_enabled = true
  tags          = local.tags
}
