output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.rg.name
}

output "vm_id" {
  description = "ID of the created VM"
  value       = azurerm_linux_virtual_machine.vm.id
}

output "vm_name" {
  description = "Name of the VM"
  value       = azurerm_linux_virtual_machine.vm.name
}

output "private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.nic.private_ip_address
}

output "public_ip" {
  description = "Public IP address of the VM"
  value       = data.azurerm_public_ip.persistent_ip.ip_address
}

output "server_ip" {
  description = "Primary IP address (kept for compatibility with existing scripts)"
  value       = data.azurerm_public_ip.persistent_ip.ip_address
}

output "fqdn" {
  description = "Fully qualified domain name"
  value       = data.azurerm_public_ip.persistent_ip.fqdn
}
