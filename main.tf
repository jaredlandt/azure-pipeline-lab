terraform {
  required_version = ">= 1.5, < 2.0"

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

provider "azurerm" {
  features {}
  # storage_use_azuread tells the provider to use AAD tokens for data-plane
  # ops (creating containers, tables) instead of storage account keys. Keeps
  # the keys-free posture even before we lock down shared_access_key_enabled.
  storage_use_azuread = true
}

locals {
  common_tags = {
    project = var.project_name
    lab     = "azure-pipeline-lab"
    managed = "terraform"
  }
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-${var.project_name}"
  location = var.location
  tags     = local.common_tags
}

module "storage" {
  source              = "./modules/storage"
  project_name        = var.project_name
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.common_tags
}

# Phase 3+ — uncomment as those modules ship:
#
# module "function" {
#   source              = "./modules/function"
#   project_name        = var.project_name
#   location            = var.location
#   resource_group_name = azurerm_resource_group.lab.name
#   storage_account_id  = module.storage.storage_account_id
#   inbox_container     = module.storage.inbox_container_name
#   table_name          = module.storage.table_name
# }
#
# module "observability" {
#   source              = "./modules/observability"
#   project_name        = var.project_name
#   location            = var.location
#   resource_group_name = azurerm_resource_group.lab.name
# }
