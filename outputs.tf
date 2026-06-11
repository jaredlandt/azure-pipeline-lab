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

output "storage_account_name" {
  description = "Queue storage account. Globally unique; varies per apply due to random suffix."
  value       = module.storage.storage_account_name
}

output "container_names" {
  description = "Map of stage name -> container name."
  value       = module.storage.container_names
}

output "table_name" {
  description = "Tickets table in Table Storage."
  value       = module.storage.table_name
}
