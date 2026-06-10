output "resource_group_name" {
  description = "Name of the lab's resource group. All other resources nest under this."
  value       = azurerm_resource_group.lab.name
}

output "resource_group_id" {
  description = "Full Azure resource ID of the lab's resource group."
  value       = azurerm_resource_group.lab.id
}

output "location" {
  description = "Azure region the lab is deployed to."
  value       = azurerm_resource_group.lab.location
}
