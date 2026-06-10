terraform {
  required_version = ">= 1.5, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-${var.project_name}"
  location = var.location

  tags = {
    project = var.project_name
    lab     = "azure-pipeline-lab"
    managed = "terraform"
  }
}

# Module skeleton — Phase 1 wires the composition; resources land in Phase 2+.
#
# module "storage" {
#   source              = "./modules/storage"
#   project_name        = var.project_name
#   location            = var.location
#   resource_group_name = azurerm_resource_group.lab.name
# }
#
# module "function" {
#   source              = "./modules/function"
#   project_name        = var.project_name
#   location            = var.location
#   resource_group_name = azurerm_resource_group.lab.name
# }
#
# module "observability" {
#   source              = "./modules/observability"
#   project_name        = var.project_name
#   location            = var.location
#   resource_group_name = azurerm_resource_group.lab.name
# }
