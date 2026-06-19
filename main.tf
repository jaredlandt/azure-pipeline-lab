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
  features {
    # Application Insights auto-creates an "Smart Detection" action group
    # inside the RG that Terraform doesn't track. Allow `destroy` to drop
    # the whole group — ephemerality is the lab's point. Phase 5 may revisit
    # for a more selective hardening posture.
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  # storage_use_azuread tells the provider to use AAD tokens for data-plane
  # ops (creating containers, tables) instead of storage account keys. Keeps
  # the keys-free posture even before we lock down shared_access_key_enabled.
  storage_use_azuread = true
}

locals {
  common_tags = {
    project     = var.project_name
    lab         = "azure-pipeline-lab"
    managed     = "terraform"
    environment = var.environment
  }
}

# The lab RG is bootstrapped by bootstrap/github_oidc.ps1 so the GitHub
# Actions SP can be scoped to it before the first apply. Terraform reads
# it as a data source; lifecycle of the RG itself lives outside state.
data "azurerm_resource_group" "lab" {
  name = "rg-${var.project_name}"
}

module "storage" {
  source              = "./modules/storage"
  project_name        = var.project_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.common_tags
}

module "function" {
  source               = "./modules/function"
  project_name         = var.project_name
  location             = var.location
  resource_group_name  = data.azurerm_resource_group.lab.name
  storage_account_id   = module.storage.storage_account_id
  storage_account_name = module.storage.storage_account_name
  inbox_container      = module.storage.container_names["inbox"]
  completed_container  = module.storage.container_names["completed"]
  table_name           = module.storage.table_name
  tags                 = local.common_tags
}

module "observability" {
  source                  = "./modules/observability"
  project_name            = var.project_name
  location                = var.location
  resource_group_name     = data.azurerm_resource_group.lab.name
  application_insights_id = module.function.application_insights_id
  tags                    = local.common_tags
}
