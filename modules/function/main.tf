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

# Function App names: global DNS namespace, 2-60 chars, alphanum+hyphens.
# Suffix for uniqueness on clone-and-apply.
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  numeric = true
  upper   = false
  special = false
}

# Y1 = Consumption tier. Pennies/mo; first 1M executions free.
resource "azurerm_service_plan" "function" {
  name                = "asp-${var.project_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = var.tags
}

# App Insights + workspace. Linux consumption has no SCM log stream, so
# without App Insights you're flying blind on import errors and trigger
# failures. Roadmap Phase 5 lifts the polish (workbook etc.) on top of this.
resource "azurerm_log_analytics_workspace" "function" {
  name                = "law-${var.project_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "function" {
  name                = "appi-${var.project_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  workspace_id        = azurerm_log_analytics_workspace.function.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_linux_function_app" "function" {
  name                = "func-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.function.id

  # AzureWebJobsStorage on MI (Phase 5 hardening — Phase 3 noted this as
  # fragile on Linux consumption but it works once the role assignments
  # propagate). storage_uses_managed_identity = true tells the Functions
  # host to authenticate to its bookkeeping storage via the system-
  # assigned identity, NOT via an account key. The MI's three storage
  # role assignments (below) cover both host bookkeeping and
  # application-level access. No connection string anywhere.
  storage_account_name          = var.storage_account_name
  storage_uses_managed_identity = true

  https_only = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    # Python v2 (decorator) programming model requires this feature flag.
    AzureWebJobsFeatureFlags = "EnableWorkerIndexing"

    # App Insights — required for visibility on Linux consumption (no SCM).
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.function.connection_string

    # Application-level config — function code reads these via os.environ.
    QUEUE_STORAGE_ACCOUNT = var.storage_account_name
    INBOX_CONTAINER       = var.inbox_container
    COMPLETED_CONTAINER   = var.completed_container
    TICKETS_TABLE         = var.table_name
  }

  # WEBSITE_RUN_FROM_PACKAGE is owned by bootstrap/deploy_function.sh after the
  # initial apply. Terraform would otherwise wipe it on the next apply because
  # azurerm manages app_settings as a whole map. The trade-off: future changes
  # to the settings above require an explicit re-apply with this ignore
  # temporarily removed (or `terraform apply -replace`). Phase 4 CI/CD reworks
  # this with a clean infra-vs-code-deploy split.
  lifecycle {
    ignore_changes = [app_settings]
  }

  tags = var.tags
}

# Role assignments on the queue storage account. The function's
# system-assigned identity needs three data-plane roles:
#
# - Storage Blob Data Owner: required by the Functions host for
#   AzureWebJobsStorage (writes to azure-webjobs-hosts) AND by application
#   code to read/write inbox + completed containers. Owner is one role
#   instead of two.
# - Storage Queue Data Contributor: the Functions host uses queues
#   internally for blob-trigger plumbing (azure-webjobs-blobtrigger).
# - Storage Table Data Contributor: application code writes ticket rows.
resource "azurerm_role_assignment" "function_blob_owner" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_linux_function_app.function.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_queue_contributor" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_linux_function_app.function.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_table_contributor" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_function_app.function.identity[0].principal_id
}
