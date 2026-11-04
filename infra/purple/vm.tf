# X-08 target: Linux VM with a user-assigned identity, no public IP and no inbound rule.
# Host logs: the Azure Monitor Agent sends all Syslog facilities to the workspace (table Syslog),
# so the run shows what, if anything, a Run Command leaves on the host side.

resource "azurerm_virtual_network" "purple" {
  count               = var.enable_vm ? 1 : 0
  name                = "vnet-huginn-purple"
  location            = azurerm_resource_group.purple.location
  resource_group_name = azurerm_resource_group.purple.name
  address_space       = ["10.43.0.0/24"]
  tags                = local.tags
}

resource "azurerm_subnet" "vm" {
  count                = var.enable_vm ? 1 : 0
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.purple.name
  virtual_network_name = azurerm_virtual_network.purple[0].name
  address_prefixes     = ["10.43.0.0/26"]
  # Outbound only: the VM agent downloads extensions and the Azure Monitor Agent sends logs.
  # New subnets are private by default; a NAT gateway would cost more than the whole run.
  default_outbound_access_enabled = true
}

resource "azurerm_network_security_group" "vm" {
  count               = var.enable_vm ? 1 : 0
  name                = "nsg-huginn-purple-vm"
  location            = azurerm_resource_group.purple.location
  resource_group_name = azurerm_resource_group.purple.name
  tags                = local.tags

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "vm" {
  count                     = var.enable_vm ? 1 : 0
  subnet_id                 = azurerm_subnet.vm[0].id
  network_security_group_id = azurerm_network_security_group.vm[0].id
}

resource "azurerm_network_interface" "vm" {
  count               = var.enable_vm ? 1 : 0
  name                = "nic-huginn-purple-vm"
  location            = azurerm_resource_group.purple.location
  resource_group_name = azurerm_resource_group.purple.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm[0].id
    private_ip_address_allocation = "Dynamic"
  }
}

# Nobody logs in: no public IP, no inbound rule. The key exists because Azure requires one.
resource "tls_private_key" "vm" {
  count     = var.enable_vm ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "target" {
  #checkov:skip=CKV_AZURE_50:Extensions are the attack surface: Run Command (X-08) and the Azure Monitor Agent are extensions (ADR 0008)
  #checkov:skip=CKV_AZURE_151:Encryption at host needs a subscription feature registration; disposable VM with no data (ADR 0008)
  count                           = var.enable_vm ? 1 : 0
  name                            = "vm-huginn-purple"
  location                        = azurerm_resource_group.purple.location
  resource_group_name             = azurerm_resource_group.purple.name
  size                            = var.vm_size
  admin_username                  = "huginn"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[0].id]
  allow_extension_operations      = true
  provision_vm_agent              = true
  tags                            = local.tags

  admin_ssh_key {
    username   = "huginn"
    public_key = tls_private_key.vm[0].public_key_openssh
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

  # System-assigned: used by the Azure Monitor Agent. User-assigned: the identity Fenrir hunts.
  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.target.id]
  }
}

resource "azurerm_virtual_machine_extension" "ama" {
  count                      = var.enable_vm ? 1 : 0
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.target[0].id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = local.tags
}

resource "azurerm_monitor_data_collection_rule" "host" {
  count               = var.enable_vm ? 1 : 0
  name                = "dcr-huginn-purple-host"
  location            = azurerm_resource_group.purple.location
  resource_group_name = azurerm_resource_group.purple.name
  kind                = "Linux"
  tags                = local.tags

  destinations {
    log_analytics {
      name                  = "law-huginn"
      workspace_resource_id = data.azurerm_log_analytics_workspace.huginn.id
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["law-huginn"]
  }

  data_sources {
    syslog {
      name           = "syslog-all"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["*"]
      log_levels     = ["*"]
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "host" {
  count                   = var.enable_vm ? 1 : 0
  name                    = "dcra-huginn-purple-host"
  target_resource_id      = azurerm_linux_virtual_machine.target[0].id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.host[0].id
}
