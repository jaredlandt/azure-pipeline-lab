output "resource_group_name" {
  description = "Name of the lab's resource group. All other resources nest under this."
  value       = data.azurerm_resource_group.lab.name
}

output "resource_group_id" {
  description = "Full Azure resource ID of the lab's resource group."
  value       = data.azurerm_resource_group.lab.id
}

output "location" {
  description = "Azure region the lab is deployed to."
  value       = data.azurerm_resource_group.lab.location
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

output "function_app_name" {
  description = "Function App name. Used by deploy_function.sh and for portal lookup."
  value       = module.function.function_app_name
}

output "function_app_hostname" {
  description = "Function App default hostname."
  value       = module.function.function_app_default_hostname
}

output "package_container_name" {
  description = "Name of the function-package container. GitHub Actions uploads release.zip here on every apply."
  value       = module.storage.package_container_name
}
