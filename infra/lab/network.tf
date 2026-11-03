# Always-on, free network for the per-run X-08 VM. No public IP anywhere, no inbound rule.

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-huginn-lab"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  address_space       = ["10.42.0.0/24"]
  tags                = local.tags
}

resource "azurerm_subnet" "vm" {
  name                 = "snet-vm"
  resource_group_name  = data.azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.42.0.0/26"]
}

# Inbound: the default rules already deny traffic from the internet; the explicit rule below
# also denies traffic from inside the VNet. Run Command reaches the VM through the VM agent and
# the Azure platform, not through the network.
resource "azurerm_network_security_group" "vm" {
  name                = "nsg-huginn-lab-vm"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
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
  subnet_id                 = azurerm_subnet.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}
