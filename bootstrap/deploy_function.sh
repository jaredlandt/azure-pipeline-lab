#!/usr/bin/env bash
# deploy_function.sh — package function_app/ and deploy via run-from-package.
#
# Linux consumption-tier Functions don't have Kudu (the SCM site), so
# `az functionapp deploy` / `config-zip` don't work. The supported path
# is to upload the zip to a blob and set WEBSITE_RUN_FROM_PACKAGE to a
# URL — the function downloads the package at warm-up.
#
# For Phase 3: SAS-authed URL with 1-hour expiry. Phase 4 (CI/CD) will
# switch to MI-based auth so no SAS is generated.
#
# Usage:
#   ./bootstrap/deploy_function.sh

set -euo pipefail

cd "$(dirname "$0")/.."

FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-$(terraform output -raw function_app_name)}"
RESOURCE_GROUP="${RESOURCE_GROUP:-$(terraform output -raw resource_group_name)}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-$(terraform output -raw storage_account_name)}"

BLOB_NAME="function-$(date +%s).zip"
ZIP="/tmp/${BLOB_NAME}"
STAGE="/tmp/azure-pipeline-lab-stage"
rm -f "$ZIP"
rm -rf "$STAGE"

echo "==> Vendoring Linux dependencies into .python_packages/"
# Linux consumption + WEBSITE_RUN_FROM_PACKAGE skips Oryx build, so deps
# must be in the zip. --platform manylinux2014_x86_64 forces Linux wheels
# (we're packaging from macOS); --only-binary=:all: refuses source dists
# that would need compilation; --python-version pins the resolver to the
# Function App's runtime (3.11).
mkdir -p "$STAGE/.python_packages/lib/site-packages"
pip3 install \
    --platform manylinux2014_x86_64 \
    --target "$STAGE/.python_packages/lib/site-packages" \
    --only-binary=:all: \
    --python-version 3.11 \
    --quiet \
    -r function_app/requirements.txt

echo "==> Copying function code"
cp function_app/function_app.py "$STAGE/"
cp function_app/host.json "$STAGE/"
cp function_app/requirements.txt "$STAGE/"

echo "==> Packaging zip"
(cd "$STAGE" && zip -r "$ZIP" . -x "*.pyc" "__pycache__/*" >/dev/null)
echo "    $(du -h "$ZIP" | cut -f1) -> $ZIP"

echo "==> Granting current user Storage Blob Data Contributor (idempotent)"
# Subscription Owner is control-plane only; the data-plane operations below
# (blob upload, SAS gen) need an explicit data-plane role. Cleaned up
# automatically when terraform destroys the storage account.
USER_OID=$(az ad signed-in-user show --query id -o tsv)
STORAGE_ID=$(az storage account show \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv)
az role assignment create \
    --assignee-object-id "$USER_OID" \
    --assignee-principal-type User \
    --role "Storage Blob Data Contributor" \
    --scope "$STORAGE_ID" \
    --output none 2>/dev/null || true

echo "==> Waiting 90s for RBAC propagation (data plane lags control plane)"
sleep 90

echo "==> Ensuring deployments container"
az storage container create \
    --account-name "$STORAGE_ACCOUNT" \
    --name deployments \
    --auth-mode login \
    --output none

echo "==> Uploading $BLOB_NAME"
az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name deployments \
    --name "$BLOB_NAME" \
    --file "$ZIP" \
    --auth-mode login \
    --overwrite \
    --output none

echo "==> Generating 1h read SAS"
EXPIRY=$(date -u -v+1H +"%Y-%m-%dT%H:%MZ" 2>/dev/null || date -u -d '+1 hour' +"%Y-%m-%dT%H:%MZ")
SAS=$(az storage blob generate-sas \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name deployments \
    --name "$BLOB_NAME" \
    --permissions r \
    --expiry "$EXPIRY" \
    --auth-mode login \
    --as-user \
    --full-uri \
    --output tsv)

echo "==> Setting WEBSITE_RUN_FROM_PACKAGE"
az functionapp config appsettings set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$FUNCTION_APP_NAME" \
    --settings "WEBSITE_RUN_FROM_PACKAGE=$SAS" \
    --output none

echo "==> Restarting function app"
az functionapp restart \
    --resource-group "$RESOURCE_GROUP" \
    --name "$FUNCTION_APP_NAME" \
    --output none

echo ""
echo "Deployed. Triggers register on next warm-up (~30-60s)."
echo "Tail logs: az webapp log tail --resource-group $RESOURCE_GROUP --name $FUNCTION_APP_NAME"
