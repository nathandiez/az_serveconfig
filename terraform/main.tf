# Azure Provider configuration
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
# Import the persistent public IP
data "azurerm_public_ip" "persistent_ip" {
  name                = "ned-serve-config-persistent"
  resource_group_name = "rg-persistent-resources"
}

provider "azurerm" {
  features {}
}

# Create resource group
resource "azurerm_resource_group" "rg" {
  name     = "rg-serve-config"
  location = var.location
  tags     = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Create virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-serve-config"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Create subnet
resource "azurerm_subnet" "subnet" {
  name                 = "subnet-serve-config"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  lifecycle {
    create_before_destroy = true
  }
}

# Create public IP
resource "azurerm_public_ip" "public_ip" {
  name                = "ned-serve-config"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  domain_name_label   = "nedserveconfig"
  tags                = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Create Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-serve-config"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  # Allow HTTP (port 80) for Let's Encrypt verification
  security_rule {
    name                       = "HTTP-80"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow SSH from your IP address only
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "151.210.118.142/32"
    destination_address_prefix = "*"
  }

  # Allow HTTP for the Flask app from specific IPs
  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5000"
    source_address_prefixes    = ["151.210.118.142/32", "52.226.134.245/32"]
    destination_address_prefix = "*"
  }

  # Allow HTTPS for the Flask app from specific IPs
  security_rule {
    name                       = "HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = ["151.210.118.142/32", "40.71.17.54/32"] # Your IP and iots6 IP
    destination_address_prefix = "*"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create network interface
resource "azurerm_network_interface" "nic" {
  name                = "nic-serve-config"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.4"
    public_ip_address_id          = data.azurerm_public_ip.persistent_ip.id
  }

  # Add explicit dependency
  depends_on = [
    azurerm_public_ip.public_ip,
    azurerm_subnet.subnet
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# Connect NSG to NIC
resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id

  # Add explicit dependency
  depends_on = [
    azurerm_network_interface.nic,
    azurerm_network_security_group.nsg
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-nedserveconfig"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.ssh_username
  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]
  tags = var.tags

  admin_ssh_key {
    username   = var.ssh_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.disk_size
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOT
#!/bin/bash
hostnamectl set-hostname nedserveconfig
EOT
  )
  # Add explicit dependency
  depends_on = [
    azurerm_network_interface.nic,
    azurerm_network_interface_security_group_association.nsg_assoc
  ]

  lifecycle {
    create_before_destroy = true
  }
}