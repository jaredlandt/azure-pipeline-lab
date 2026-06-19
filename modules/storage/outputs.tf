output "storage_account_id" {
  description = "Full resource ID of the queue storage account. Used by the function module for RBAC role assignment scope."
  value       = azurerm_storage_account.queue.id
}

output "storage_account_name" {
  description = "Globally-unique storage account name. Used by the function module's app settings (AzureWebJobsStorage)."
  value       = azurerm_storage_account.queue.name
}

output "primary_blob_endpoint" {
  description = "Blob service endpoint, e.g. https://<account>.blob.core.windows.net/. Used by clients and the function trigger."
  value       = azurerm_storage_account.queue.primary_blob_endpoint
}

output "container_names" {
  description = "Map of stage -> container name for all four queue containers."
  value       = { for k, c in azurerm_storage_container.stages : k => c.name }
}

output "inbox_container_name" {
  description = "Name of the inbox container — the blob-trigger source in Phase 3."
  value       = azurerm_storage_container.stages["inbox"].name
}

output "table_name" {
  description = "Name of the tickets table."
  value       = azurerm_storage_table.tickets.name
}

output "package_container_name" {
  description = "Name of the function deployment-package container. GitHub Actions uploads the zip here and points WEBSITE_RUN_FROM_PACKAGE at it (unsigned URL — Function App MI provides read auth)."
  value       = azurerm_storage_container.package.name
}

output "primary_access_key" {
  description = "Primary access key. Used by AzureWebJobsStorage (the Functions host's bookkeeping storage). Application-level access still uses MI. Phase 5 hardening swaps the host to MI too."
  value       = azurerm_storage_account.queue.primary_access_key
  sensitive   = true
}
