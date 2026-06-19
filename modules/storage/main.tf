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

# Storage account names must be globally unique across all of Azure, 3-24
# chars, lowercase + digits only. Strip hyphens from project_name and append
# a short random suffix so this config applies cleanly in any subscription.
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  numeric = true
  upper   = false
  special = false
}

resource "azurerm_storage_account" "queue" {
  name                            = "st${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  # Phase 5 hardening: disable account keys entirely. Every caller — Terraform
  # (storage_use_azuread = true on the provider), the Functions host
  # (storage_uses_managed_identity = true), the GitHub Actions deploy step
  # (--auth-mode login), application code (DefaultAzureCredential) — already
  # uses AAD/MI. With keys disabled, leaked-credential blast radius collapses
  # to "whatever the SP/MI can reach within its scoped roles."
  shared_access_key_enabled = false

  tags = var.tags
}

# Four containers — the queue stages. Mirrors MncRydr's queue/ folder
# topology (inbox / in-process / completed / failed).
resource "azurerm_storage_container" "stages" {
  for_each              = toset(["inbox", "in-process", "completed", "failed"])
  name                  = each.key
  storage_account_id    = azurerm_storage_account.queue.id
  container_access_type = "private"
}

# Deployment artifact container. Holds the zipped function package that
# WEBSITE_RUN_FROM_PACKAGE points at. Kept off the stages for_each because
# it isn't part of the ticket-flow vocabulary; mixing it in would make a
# reorder of the stages set churn this container's state too.
resource "azurerm_storage_container" "package" {
  name                  = "function-package"
  storage_account_id    = azurerm_storage_account.queue.id
  container_access_type = "private"
}

# Table storage — ticket record store. SQLite's spiritual successor.
#
# Note: azurerm_storage_table v4.76 still requires storage_account_name, while
# the container resource migrated to storage_account_id. Inconsistent within
# the same provider, but correct as of v4.76 — re-check on the next major bump.
resource "azurerm_storage_table" "tickets" {
  name                 = "tickets"
  storage_account_name = azurerm_storage_account.queue.name
}
