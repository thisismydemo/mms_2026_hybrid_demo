##############################################################################
# 00-setup-identity.ps1  — One-time bootstrap of the deployment managed identity
#
# Run this ONCE from any machine with 'az login' already done.
# ("you have access already" — just needs az login to the tplabs tenant)
#
# What this does:
#   1. Deploys identity.bicep  → creates mi-hvlab-deploy-eus-01 with GitHub
#      Actions federated credentials (no app registration, no client secret)
#   2. Assigns Key Vault Secrets User on kv-tplabs-platform (cross-subscription)
#      so getSecret() in tplabs.bicepparam resolves during Bicep deployment
#   3. Prints the 3 GitHub Actions secrets you need to set in the repo
#
# After running:
#   - Copy AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID from output
#   - Set them in: https://github.com/thisismydemo/mms_2026_hybrid_demo/settings/secrets/actions
#   - That's it. No app registration. No client secret. No portal clicks.
##############################################################################

param(
    [string]$DeploySubId   = '00cd4357-ed45-4efb-bee0-10c467ff994b',
    [string]$TplabsSubId   = '2caa0b8a-a1d6-4f0c-8c03-861787b8315c',
    [string]$TenantId      = 'a9b67171-3fbb-45bf-8394-eb56d02a86e4',
    [string]$Location      = 'eastus',
    [string]$KVName        = 'kv-tplabs-platform',
    [string]$KVRg          = 'rg-c01-platform-eus-01'
)

$ErrorActionPreference = 'Stop'
Write-Host "=== HV-Lab Identity Bootstrap ===" -ForegroundColor Cyan
Write-Host "No app registration. No client secret. Just a managed identity." -ForegroundColor DarkGray

# ── Step 1: Deploy identity.bicep ────────────────────────────────────────────
Write-Host "`n[1/3] Deploying deployment managed identity (mi-hvlab-deploy-eus-01)..."

$deployOutput = az deployment sub create `
    --subscription $DeploySubId `
    --location     $Location `
    --template-file (Join-Path $PSScriptRoot '..\bicep\identity.bicep') `
    --parameters location=$Location `
    --name "hvlab-identity-setup" `
    --output json | ConvertFrom-Json

$clientId    = $deployOutput.properties.outputs.identityClientId.value
$principalId = $deployOutput.properties.outputs.identityPrincipalId.value

Write-Host "  ✅ Managed identity created"
Write-Host "     Client ID:    $clientId"
Write-Host "     Principal ID: $principalId"

# ── Step 2: Assign Key Vault Secrets User on kv-tplabs-platform ──────────────
# Cross-subscription: KV is in tplabs hub sub, deployment is in the lab sub.
Write-Host "`n[2/3] Assigning Key Vault Secrets User on $KVName (cross-subscription)..."

$kvId = az keyvault show `
    --name $KVName `
    --resource-group $KVRg `
    --subscription $TplabsSubId `
    --query id -o tsv

az role assignment create `
    --role "Key Vault Secrets User" `
    --assignee-object-id $principalId `
    --assignee-principal-type ServicePrincipal `
    --scope $kvId `
    --subscription $TplabsSubId | Out-Null

Write-Host "  ✅ Key Vault Secrets User assigned on $KVName"
Write-Host "     Allows Bicep getSecret() to resolve secrets during deployment"

# ── Step 3: Print GitHub secrets to set ──────────────────────────────────────
Write-Host "`n[3/3] GitHub Actions secrets to set in the repo..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  Go to: https://github.com/thisismydemo/mms_2026_hybrid_demo/settings/secrets/actions"
Write-Host ""
Write-Host "  Set these 3 secrets (no others needed):" -ForegroundColor Cyan
Write-Host ""
Write-Host "  AZURE_CLIENT_ID       = $clientId" -ForegroundColor Green
Write-Host "  AZURE_TENANT_ID       = $TenantId" -ForegroundColor Green
Write-Host "  AZURE_SUBSCRIPTION_ID = $DeploySubId" -ForegroundColor Green
Write-Host ""
Write-Host "  No AZURE_CLIENT_SECRET. No app registration. Just these 3 values." -ForegroundColor DarkGray

# Optionally set them via gh CLI if available
$ghAvailable = Get-Command gh -ErrorAction SilentlyContinue
if ($ghAvailable) {
    $setSecrets = Read-Host "`nDetected 'gh' CLI. Set these secrets automatically? [Y/n]"
    if ($setSecrets -ne 'n') {
        gh secret set AZURE_CLIENT_ID       --body $clientId       --repo thisismydemo/mms_2026_hybrid_demo
        gh secret set AZURE_TENANT_ID       --body $TenantId       --repo thisismydemo/mms_2026_hybrid_demo
        gh secret set AZURE_SUBSCRIPTION_ID --body $DeploySubId    --repo thisismydemo/mms_2026_hybrid_demo
        Write-Host "  ✅ GitHub secrets set via gh CLI" -ForegroundColor Green
    }
}

Write-Host @"

✅ Identity bootstrap complete.

Summary:
  Managed identity: mi-hvlab-deploy-eus-01
  Federated creds:  main branch + workflow_dispatch (environment: hvlab)
  Roles:            Contributor + User Access Administrator (deployment sub)
                    Key Vault Secrets User (kv-tplabs-platform, tplabs sub)

You are ready to trigger workflow: HVLab 01 — Deploy Azure Infrastructure
"@
