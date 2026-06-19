terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Azure Monitor Workbooks are identified by a GUID, not a name. Use
# random_uuid so the workbook lives across re-applies in one workspace,
# and `keepers` so it never churns just because something else changed.
resource "random_uuid" "workbook" {
  keepers = {
    project_name = var.project_name
  }
}

# Workbook — three tiles + a markdown intro, all KQL against the
# Application Insights `requests` table for the `route_ticket` function.
#
# The dashboard's spiritual successor: read-only, three numbers — ingest,
# failure rate, p95 duration. MncRydr's serve_dashboard.py was the same
# shape (counts + failures + latency); this is the cloud-native rebuild,
# not a redesign.
resource "azurerm_application_insights_workbook" "pipeline_health" {
  name                = random_uuid.workbook.result
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "${var.project_name} — pipeline health"
  source_id           = lower(var.application_insights_id)
  category            = "workbook"
  tags                = var.tags

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# ${var.project_name} — pipeline health\n\nRead-only view of the ticket pipeline. KQL against App Insights' `requests` table for the `route_ticket` blob trigger. Window: last 24h.\n\nThree questions: **how many tickets came in**, **how many failed**, **how slow is the slow path** (p95 duration)."
        }
        name = "intro"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "requests | where operation_Name == 'route_ticket' | summarize Tickets = count() by bin(timestamp, 1h) | render columnchart"
          size         = 0
          title        = "Ticket ingest (per hour, last 24h)"
          queryType    = 0
          resourceType = "microsoft.insights/components"
          timeContext  = { durationMs = 86400000 }
        }
        name = "ingest-count"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "requests | where operation_Name == 'route_ticket' | summarize Total = count(), Failed = countif(success == false) by bin(timestamp, 1h) | extend FailurePct = iff(Total == 0, 0.0, round(100.0 * todouble(Failed) / todouble(Total), 2)) | project timestamp, Total, Failed, FailurePct | render timechart"
          size         = 0
          title        = "Failure rate (per hour, last 24h)"
          queryType    = 0
          resourceType = "microsoft.insights/components"
          timeContext  = { durationMs = 86400000 }
        }
        name = "failure-rate"
      },
      {
        type = 3
        content = {
          version      = "KqlItem/1.0"
          query        = "requests | where operation_Name == 'route_ticket' | summarize p50 = percentile(duration, 50), p95 = percentile(duration, 95), p99 = percentile(duration, 99) by bin(timestamp, 1h) | render timechart"
          size         = 0
          title        = "Duration (ms) — p50 / p95 / p99"
          queryType    = 0
          resourceType = "microsoft.insights/components"
          timeContext  = { durationMs = 86400000 }
        }
        name = "duration"
      }
    ]
    isLocked            = false
    fallbackResourceIds = [var.application_insights_id]
  })
}
