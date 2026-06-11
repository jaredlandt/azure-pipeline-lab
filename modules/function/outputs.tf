output "function_app_name" {
  description = "Name of the Function App. Used by the deploy script and for portal lookup."
  value       = azurerm_linux_function_app.function.name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App (e.g. func-<name>.azurewebsites.net)."
  value       = azurerm_linux_function_app.function.default_hostname
}

output "principal_id" {
  description = "Object ID of the function's system-assigned managed identity. Useful for auditing role assignments."
  value       = azurerm_linux_function_app.function.identity[0].principal_id
}
