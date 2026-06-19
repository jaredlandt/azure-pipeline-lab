output "workbook_id" {
  description = "Full resource ID of the pipeline-health workbook. Open in the portal: Application Insights -> Workbooks -> Public."
  value       = azurerm_application_insights_workbook.pipeline_health.id
}

output "workbook_name" {
  description = "Workbook GUID. Same as the name field; surfaced for direct portal-URL construction."
  value       = azurerm_application_insights_workbook.pipeline_health.name
}
