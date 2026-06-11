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
