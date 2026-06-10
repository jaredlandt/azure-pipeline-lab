terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstate264a102a"
    container_name       = "tfstate"
    key                  = "azure-pipeline-lab.tfstate"
    use_azuread_auth     = true
  }
}
