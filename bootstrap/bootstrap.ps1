#!/usr/bin/env pwsh
# bootstrap.ps1 — provisions the Terraform remote-state backend.
#
# Why a script (not Terraform): a Terraform-managed backend needs somewhere to
# store its own state. Local state works but leaks storage keys into a tfstate
# file that has to be gitignored — a fresh clone then can't manage the backend.
# A script has no state to leak. Run once per subscription; every command is
# create-if-missing, so re-running is safe.
#
# Usage:
#   pwsh ./bootstrap/bootstrap.ps1
#   pwsh ./bootstrap/bootstrap.ps1 -Location eastus -ProjectName azure-pipeline-lab

[CmdletBinding()]
param(
    [string]$ProjectName = "azure-pipeline-lab",
    [string]$Location    = "centralus",
    [string]$RgName      = "rg-tfstate",
    [string]$Container   = "tfstate"
)

$ErrorActionPreference = "Stop"

# Storage account names: 3-24 chars, lowercase+digits, globally unique.
# Derive a short stable name from the subscription ID so re-runs hit the same account.
$SubId = az account show --query id -o tsv
if (-not $SubId) { throw "az not logged in. Run 'az login' first." }
$Suffix = ($SubId -replace '[^a-z0-9]', '').Substring(0, 8)
$StorageAccount = "sttfstate$Suffix"

Write-Host "Subscription:      $SubId"
Write-Host "Resource group:    $RgName ($Location)"
Write-Host "Storage account:   $StorageAccount"
Write-Host "Container:         $Container"
Write-Host ""

# Resource group (idempotent: az group create returns 200 whether new or existing).
Write-Host "==> Resource group"
az group create --name $RgName --location $Location --output none

# Storage account. `az storage account create` is idempotent on name+rg.
Write-Host "==> Storage account"
az storage account create `
    --name $StorageAccount `
    --resource-group $RgName `
    --location $Location `
    --sku Standard_LRS `
    --kind StorageV2 `
    --min-tls-version TLS1_2 `
    --allow-blob-public-access false `
    --output none

# Blob versioning — recovery from corrupted state.
Write-Host "==> Blob versioning"
az storage account blob-service-properties update `
    --account-name $StorageAccount `
    --resource-group $RgName `
    --enable-versioning true `
    --output none

# Container. --auth-mode login uses the caller's Entra identity (no keys).
Write-Host "==> Container"
az storage container create `
    --name $Container `
    --account-name $StorageAccount `
    --auth-mode login `
    --output none

# Data-plane RBAC for the bootstrapping user. Subscription Owner is a
# control-plane role and does NOT grant blob read/write. Terraform's azurerm
# backend with use_azuread_auth = true needs Storage Blob Data Contributor.
Write-Host "==> Data-plane RBAC (Storage Blob Data Contributor)"
$UserOid = az ad signed-in-user show --query id -o tsv
$AccountId = az storage account show --name $StorageAccount --resource-group $RgName --query id -o tsv
az role assignment create `
    --assignee-object-id $UserOid `
    --assignee-principal-type User `
    --role "Storage Blob Data Contributor" `
    --scope $AccountId `
    --output none 2>$null
# Suppress error on re-run: az returns non-zero if the assignment already exists.

Write-Host ""
Write-Host "Backend ready. Use in backend.tf:"
Write-Host ""
Write-Host "  terraform {"
Write-Host "    backend `"azurerm`" {"
Write-Host "      resource_group_name  = `"$RgName`""
Write-Host "      storage_account_name = `"$StorageAccount`""
Write-Host "      container_name       = `"$Container`""
Write-Host "      key                  = `"$ProjectName.tfstate`""
Write-Host "      use_azuread_auth     = true"
Write-Host "    }"
Write-Host "  }"
