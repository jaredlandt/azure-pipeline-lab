#!/usr/bin/env pwsh
# github_oidc.ps1 — bootstraps the Entra ID app registration + federated
# credentials that GitHub Actions uses to authenticate to Azure via OIDC.
#
# Why a script (not Terraform): the SP that runs Terraform is what Terraform
# would otherwise create — circular. Same chicken-and-egg as bootstrap.ps1
# (the backend can't store its own state). Run once per subscription; every
# command is create-if-missing, so re-running is safe.
#
# Scope of the resulting SP (least privilege — see Phase 4 plan):
#   - Storage Blob Data Contributor on the tfstate storage account
#   - Contributor on the lab resource group only
#   - User Access Administrator on the lab resource group (required so
#     Terraform can create role assignments for the Function App MI)
#   - Storage Blob Data Contributor on the lab resource group (so the
#     CI deploy step can upload the function package zip — the lab SA
#     name is Terraform-controlled with a random suffix, so granting at
#     RG scope covers it without coupling to the suffix)
#
# Usage:
#   pwsh ./bootstrap/github_oidc.ps1
#   pwsh ./bootstrap/github_oidc.ps1 -GitHubOrg jaredlandt -GitHubRepo azure-pipeline-lab

[CmdletBinding()]
param(
    [string]$ProjectName = "azure-pipeline-lab",
    [string]$Location    = "centralus",
    [string]$GitHubOrg   = "jaredlandt",
    [string]$GitHubRepo  = "azure-pipeline-lab",
    [string]$AppName     = "azure-pipeline-lab-gha",
    [string]$TfStateRg   = "rg-tfstate",
    # When set, also grants the signed-in user Storage Blob Data Contributor
    # at lab RG scope so local smoke tests (drop a ticket into inbox) work
    # without a separate role assignment. Owner is control-plane only; this
    # lesson resurfaces every phase (see Phase 1 & Phase 4 field notes).
    [switch]$GrantLocalUserDataPlane
)

$ErrorActionPreference = "Stop"

$SubId = az account show --query id -o tsv
if (-not $SubId) { throw "az not logged in. Run 'az login' first." }
$TenantId = az account show --query tenantId -o tsv

$LabRg = "rg-$ProjectName"

Write-Host "Subscription:      $SubId"
Write-Host "Tenant:            $TenantId"
Write-Host "Lab RG:            $LabRg ($Location)"
Write-Host "App registration:  $AppName"
Write-Host "GitHub:            $GitHubOrg/$GitHubRepo"
Write-Host ""

# Lab resource group. Terraform reads it as a data source — bootstrap owns it
# so the SP can be scoped to it before the first apply.
Write-Host "==> Lab resource group"
az group create --name $LabRg --location $Location --output none

# App registration. Idempotent: query existing, create only if missing.
Write-Host "==> App registration"
$AppId = az ad app list --display-name $AppName --query "[0].appId" -o tsv
if (-not $AppId) {
    $AppId = az ad app create --display-name $AppName --query appId -o tsv
    Write-Host "    created $AppId"
} else {
    Write-Host "    exists  $AppId"
}

# Service principal (the runtime identity behind the app registration).
Write-Host "==> Service principal"
$SpOid = az ad sp list --filter "appId eq '$AppId'" --query "[0].id" -o tsv
if (-not $SpOid) {
    $SpOid = az ad sp create --id $AppId --query id -o tsv
    Write-Host "    created $SpOid"
} else {
    Write-Host "    exists  $SpOid"
}

# Federated identity credentials — one per GitHub trigger we care about.
# Subject claims must match exactly what GitHub's OIDC token presents.
Write-Host "==> Federated credentials"
$Creds = @(
    @{
        Name    = "github-pr"
        Subject = "repo:$GitHubOrg/$GitHubRepo`:pull_request"
        Desc    = "Pull request runs from $GitHubOrg/$GitHubRepo"
    },
    @{
        Name    = "github-main"
        Subject = "repo:$GitHubOrg/$GitHubRepo`:ref:refs/heads/main"
        Desc    = "Pushes to main from $GitHubOrg/$GitHubRepo"
    }
)
foreach ($Cred in $Creds) {
    $Existing = az ad app federated-credential list --id $AppId --query "[?name=='$($Cred.Name)'].name" -o tsv
    if ($Existing) {
        Write-Host "    exists  $($Cred.Name)"
        continue
    }
    $Body = @{
        name        = $Cred.Name
        issuer      = "https://token.actions.githubusercontent.com"
        subject     = $Cred.Subject
        description = $Cred.Desc
        audiences   = @("api://AzureADTokenExchange")
    } | ConvertTo-Json -Compress
    $TempFile = New-TemporaryFile
    $Body | Out-File -FilePath $TempFile -Encoding utf8
    az ad app federated-credential create --id $AppId --parameters "@$TempFile" --output none
    Remove-Item $TempFile
    Write-Host "    created $($Cred.Name)"
}

# Role assignments. Idempotent: az returns non-zero if assignment exists, swallow.
Write-Host "==> Role assignments"

# 1. tfstate access — read/write the remote state blob.
$TfStateScope = "/subscriptions/$SubId/resourceGroups/$TfStateRg"
$TfStateSa = az storage account list --resource-group $TfStateRg --query "[0].id" -o tsv
if (-not $TfStateSa) {
    throw "No storage account found in $TfStateRg. Run bootstrap.ps1 first."
}
az role assignment create `
    --assignee-object-id $SpOid `
    --assignee-principal-type ServicePrincipal `
    --role "Storage Blob Data Contributor" `
    --scope $TfStateSa `
    --output none 2>$null
Write-Host "    Storage Blob Data Contributor on tfstate SA"

# 2. Lab RG — Contributor lets Terraform CRUD anything inside it.
$LabRgScope = "/subscriptions/$SubId/resourceGroups/$LabRg"
az role assignment create `
    --assignee-object-id $SpOid `
    --assignee-principal-type ServicePrincipal `
    --role "Contributor" `
    --scope $LabRgScope `
    --output none 2>$null
Write-Host "    Contributor on $LabRg"

# 3. Lab RG — User Access Administrator lets Terraform create role
# assignments for the Function App's managed identity (modules/function:117).
# Without this, plan succeeds but apply fails when it tries to assign the
# Storage Blob Data Owner role to the function's MI.
az role assignment create `
    --assignee-object-id $SpOid `
    --assignee-principal-type ServicePrincipal `
    --role "User Access Administrator" `
    --scope $LabRgScope `
    --output none 2>$null
Write-Host "    User Access Administrator on $LabRg"

# 4. Lab RG — Storage Blob Data Contributor lets the CI deploy step
# upload the function package zip with --auth-mode login. Granted at RG
# scope because the SA name has a Terraform-random suffix; scoping to RG
# avoids coupling the bootstrap script to that suffix.
az role assignment create `
    --assignee-object-id $SpOid `
    --assignee-principal-type ServicePrincipal `
    --role "Storage Blob Data Contributor" `
    --scope $LabRgScope `
    --output none 2>$null
Write-Host "    Storage Blob Data Contributor on $LabRg"

# Optional: grant the local user data-plane access for smoke tests.
if ($GrantLocalUserDataPlane) {
    Write-Host "==> Local user data-plane access"
    $UserOid = az ad signed-in-user show --query id -o tsv
    az role assignment create `
        --assignee-object-id $UserOid `
        --assignee-principal-type User `
        --role "Storage Blob Data Contributor" `
        --scope $LabRgScope `
        --output none 2>$null
    Write-Host "    Storage Blob Data Contributor on $LabRg (current user)"
}

# Emit literal `gh variable set` commands. `gh` is cwd-aware, so as long
# as the operator runs these from the lab repo's working directory the
# variables land on the right repo automatically — no copy-paste-into-
# wrong-tab failure mode (Phase 4 field note).
Write-Host ""
Write-Host "Done. From inside the repo (cd $GitHubRepo first), run:"
Write-Host ""
Write-Host "  gh variable set AZURE_CLIENT_ID --body '$AppId'"
Write-Host "  gh variable set AZURE_TENANT_ID --body '$TenantId'"
Write-Host "  gh variable set AZURE_SUBSCRIPTION_ID --body '$SubId'"
Write-Host ""
Write-Host "No client secret is generated — that's the point of OIDC."
