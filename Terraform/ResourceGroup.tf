provider "azurerm" {}

# First we create a resource group to keep all of the things we're creating in one, clean space.
resource "azurerm_resource_group" "network" {
  name     = "CI-CD-Playground"
  location = "Central US"
}

# Creating Key Vault to manage secrets
resource "azurerm_key_vault" "network" {
  name                = "Playground-Key-Vault"
  resource_group_name = "${azurerm_resource_group.network.name}"
  location            = "${azurerm_resource_group.network.location}"
  tenant_id           = "52a78b03-d21d-4fcb-96bb-d26737528ce5"

  sku = {
    name = "standard"
  }
}

# Creating a virtual network to link up and protect our devices
resource "azurerm_virtual_network" "network" {
  name                = "playground-network"
  address_space       = ["10.0.0.0/16"]
  location            = "${azurerm_resource_group.network.location}"
  resource_group_name = "${azurerm_resource_group.network.name}"
}

# Creating an internal subnet, our machines will go here.
resource "azurerm_subnet" "network-int" {
  name                 = "example-subnet"
  resource_group_name  = "${azurerm_resource_group.network.name}"
  virtual_network_name = "${azurerm_virtual_network.network.name}"
  address_prefix       = "10.0.1.0/24"
}

# Gateway subnet creation, allows us to connect to the network and talk to the machines
resource "azurerm_subnet" "network-gw" {
  name                 = "GatewaySubnet"
  resource_group_name  = "${azurerm_resource_group.network.name}"
  virtual_network_name = "${azurerm_virtual_network.network.name}"
  address_prefix       = "10.0.2.0/24"
}

# Creating the Ubuntu machine's network interface, connects the machine to the subnet
resource "azurerm_network_interface" "network-ni-ubuntu" {
  name                = "ubuntu-ni"
  location            = "${azurerm_resource_group.network.location}"
  resource_group_name = "${azurerm_resource_group.network.name}"

  ip_configuration {
    name                          = "kubernetes-ip-configuration"
    subnet_id                     = "${azurerm_subnet.network-int.id}"
    private_ip_address_allocation = "dynamic"
  }
}

# Creating the Windows Server 2016 machine's network interface
resource "azurerm_network_interface" "network-ni-windows" {
  name                = "windows-ni"
  location            = "${azurerm_resource_group.network.location}"
  resource_group_name = "${azurerm_resource_group.network.name}"

  ip_configuration {
    name                          = "kubernetes-ip-configuration"
    subnet_id                     = "${azurerm_subnet.network-int.id}"
    private_ip_address_allocation = "dynamic"
  }
}

# Create a public IP address from which we can access the network gateway
resource "azurerm_public_ip" "gateway-ip" {
  name                         = "gateway-ip"
  location                     = "${azurerm_resource_group.network.location}"
  resource_group_name          = "${azurerm_resource_group.network.name}"
  public_ip_address_allocation = "dynamic"
}

# Creating a network VPN gateway to allow VPN access to the network
resource "azurerm_virtual_network_gateway" "network-gateway" {
  name                = "playground-gateway"
  resource_group_name = "${azurerm_resource_group.network.name}"
  location            = "${azurerm_resource_group.network.location}"
  type                = "vpn"
  sku                 = "basic"

  ip_configuration {
    name                          = "pg-gw-config"
    public_ip_address_id          = "${azurerm_public_ip.gateway-ip.id}"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = "${azurerm_subnet.network-gw.id}"
  }
}

# Get your IP to use in local network gateway
data "http" "icanhazip" {
  url = "http://icanhazip.com"
}

# Create a local network gateway, use your computer's public IP
resource "azurerm_local_network_gateway" "computer_local" {
  name                = "onpremise"
  location            = "${azurerm_resource_group.network.location}"
  resource_group_name = "${azurerm_resource_group.network.name}"
  gateway_address     = "${replace(data.http.icanhazip.body, "\n", "")}"
  address_space       = ["10.1.1.0/24"]
}

# Make the connection
resource "azurerm_virtual_network_gateway_connection" "onpremise" {
  name                = "onpremise"
  location            = "${azurerm_resource_group.network.location}"
  resource_group_name = "${azurerm_resource_group.network.name}"

  type                       = "IPsec"
  virtual_network_gateway_id = "${azurerm_virtual_network_gateway.network-gateway.id}"
  local_network_gateway_id   = "${azurerm_local_network_gateway.computer_local.id}"

  shared_key = "4-v3ry-53cr37-1p53c-5h4r3d-k3y"
}

resource "azurerm_virtual_machine" "Windows2016" {
  name                  = "Windows2016"
  location              = "${azurerm_resource_group.network.location}"
  resource_group_name   = "${azurerm_resource_group.network.name}"
  vm_size               = "Standard_B1s"
  network_interface_ids = ["${azurerm_network_interface.network-ni-windows.id}"]

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter-Server-Core"
    version   = "latest"
  }

  storage_os_disk {
    name          = "Windows2016-osdisk"
    create_option = "FromImage"
    disk_size_gb  = 250
  }

  os_profile {
    computer_name  = "Windows2016"
    admin_username = "WindowsAdmin"
    admin_password = "Password1234!"
  }

  provisioner "remote-exec" {
    scripts = [
      "./scripts/windows/provision.ps1",
    ]

    connection = {
      type     = "winrm"
      user     = "WindowsAdmin"
      host     = "${azurerm_network_interface.network-ni-windows.private_ip_address}"
      password = "Password1234!"
    }
  }

  depends_on = [
    "azurerm_virtual_network_gateway.network-gateway",
    "azurerm_local_network_gateway.computer_local",
  ]

  os_profile_windows_config {}
}

resource "azurerm_virtual_machine" "Ubuntu" {
  name                  = "Ubuntu-Example-1"
  location              = "${azurerm_resource_group.network.location}"
  resource_group_name   = "${azurerm_resource_group.network.name}"
  vm_size               = "Standard_B1s"
  network_interface_ids = ["${azurerm_network_interface.network-ni-ubuntu.id}"]

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name          = "Ubuntu-osdisk"
    create_option = "FromImage"
    disk_size_gb  = 80
  }

  os_profile {
    computer_name  = "UbuntuExample-1"
    admin_username = "ubuntu"
    admin_password = "Password1234!"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
}
