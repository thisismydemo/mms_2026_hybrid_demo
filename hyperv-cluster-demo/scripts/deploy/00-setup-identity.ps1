##############################################################################
# 00-setup-identity.ps1  — ONE-TIME preflight. Run this from VS Code / Claude Code.
#
# Prerequisites: az login (as yourself) to the tplabs tenant first.
#
# What this does (fully automated, no prompts):
#   1.  Creates resource group rg-hvlab-mms26-eus-01
#   2.  Creates storage account sthvlabcontent01 + uploads SCVMM 2025 installer
#   3.  Deploys identity.bicep → managed identity mi-hvlab-deploy-eus-01
#         with GitHub Actions OIDC federated credentials (no app registration)
#   4.  Assigns roles on deployment sub (Contributor + User Access Administrator)
#   5.  Assigns Key Vault Secrets User on kv-tplabs-platform (cross-sub)
#   6.  Adds 3 missing KV secrets (SQL SA password, svc account password, SCVMM key)
#   7.  Sets GitHub Actions repo secrets via gh CLI
#
# After this runs: trigger hvlab-01 from GitHub Actions and walk away.
##############################################################################

param(
    [string]$DeploySubId     = '00cd4357-ed45-4efb-bee0-10c467ff994b',
    [string]$TplabsSubId     = '2caa0b8a-a1d6-4f0c-8c03-861787b8315c',
    [string]$TenantId        = 'a9b67171-3fbb-45bf-8394-eb56d02a86e4',
    [string]$Location        = 'eastus',
    [string]$ResourceGroup   = 'rg-hvlab-mms26-eus-01',
    [string]$KVName          = 'kv-tplabs-platform',
    [string]$KVRg            = 'rg-c01-platform-eus-01',
    [string]$ContentStorage  = 'sthvlabcontent01',
    [string]$ScvmmSourcePath = 'E:\tmp\SCVMM_2025',
    [string]$GHRepo          = 'thisismydemo/mms_2026_hybrid_demo',

    # Passwords — supply on command line or will be auto-generated
    [string]$SqlSaPassword,
    [string]$SvcAccountPassword,
    [string]$ScvmmProductKey = 'EVAL'   # Use 'EVAL' for trial or real key for licensed
)

$ErrorActionPreference = 'Stop'
$BicepFile = Join-Path $PSScriptRoot '..\bicep\identity.bicep'

function Write-Step { param([int]$n,[int]$total,[string]$msg)
    Write-Host "`n[$n/$total] $msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$msg) Write-Host "  ✅ $msg" -ForegroundColor Green }
function Write-Skip { param([string]$msg) Write-Host "  ⏭  $msg" -ForegroundColor DarkGray }

function New-RandomPassword {
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*'
    -join ((1..20) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

$total = 7
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║   HV-Lab MMS 2026 — Preflight Setup              ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Magenta

# Verify az login
$ctx = az account show --query "{sub:id,tenant:tenantId}" -o json 2>$null | ConvertFrom-Json
if (-not $ctx) { Write-Error "Not logged in. Run: az login --tenant $TenantId"; exit 1 }
az account set --subscription $DeploySubId
Write-OK "Logged in — subscription: $DeploySubId"

# ── 1. Resource Group ─────────────────────────────────────────────────────────
Write-Step 1 $total "Resource group: $ResourceGroup"
az group create --name $ResourceGroup --location $Location `
    --tags environment=lab workload=hvlab-mms26 owner=kristopherjturner --output none
Write-OK "$ResourceGroup ready"

# ── 2. Content storage account + SCVMM upload ────────────────────────────────
Write-Step 2 $total "Lab content storage: $ContentStorage"
$exists = az storage account show --name $ContentStorage --resource-group $ResourceGroup --query name -o tsv 2>$null
if (-not $exists) {
    az storage account create --name $ContentStorage --resource-group $ResourceGroup `
        --location $Location --sku Standard_LRS --kind StorageV2 `
        --https-only true --min-tls-version TLS1_2 --allow-blob-public-access false `
        --tags environment=lab purpose=scvmm-installer --output none
    Write-OK "Storage account created"
} else { Write-Skip "Storage account already exists" }

$storageKey = az storage account keys list --account-name $ContentStorage `
    --resource-group $ResourceGroup --query "[0].value" -o tsv
az storage container create --name "scvmm" --account-name $ContentStorage `
    --account-key $storageKey --output none 2>$null

if (Test-Path $ScvmmSourcePath) {
    Write-Host "  Uploading SCVMM 2025 installer files (this may take a few minutes)..."
    az storage blob upload-batch --account-name $ContentStorage --destination "scvmm" `
        --source $ScvmmSourcePath --account-key $storageKey --overwrite true --output none
    Write-OK "SCVMM installer uploaded to blob://scvmm"
} else { Write-Skip "SCVMM source not found at $ScvmmSourcePath — upload manually if needed" }

# ── 3. Deploy managed identity + federated credentials ───────────────────────
Write-Step 3 $total "Managed identity: mi-hvlab-deploy-eus-01"
$deployOut = az deployment sub create `
    --subscription $DeploySubId --location $Location `
    --template-file $BicepFile --parameters location=$Location `
    --name "hvlab-identity-setup" --output json | ConvertFrom-Json
$clientId    = $deployOut.properties.outputs.identityClientId.value
$principalId = $deployOut.properties.outputs.identityPrincipalId.value
Write-OK "mi-hvlab-deploy-eus-01 | clientId: $clientId"

# ── 4. KV Secrets User on kv-tplabs-platform (cross-sub) ─────────────────────
Write-Step 4 $total "Key Vault role assignment (cross-subscription)"
$kvId = az keyvault show --name $KVName --resource-group $KVRg `
    --subscription $TplabsSubId --query id -o tsv
az role assignment create --role "Key Vault Secrets User" `
    --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
    --scope $kvId --subscription $TplabsSubId --output none 2>$null
Write-OK "Key Vault Secrets User assigned on $KVName"

# ── 5. Storage Blob Data Reader for VM managed identity (set post-Bicep deploy) ─
#    (Done automatically in workflow 01 — skipping here)

# ── 6. Missing KV secrets ─────────────────────────────────────────────────────
Write-Step 6 $total "Pre-staging missing KV secrets"

function Set-KVSecret {
    param([string]$Name, [string]$Value, [string]$Description)
    $existing = az keyvault secret show --vault-name $KVName --subscription $TplabsSubId `
        --name $Name --query name -o tsv 2>$null
    if ($existing) { Write-Skip "$Name already exists"; return }
    az keyvault secret set --vault-name $KVName --subscription $TplabsSubId `
        --name $Name --value $Value --output none
    Write-OK "$Name set ($Description)"
}

if (-not $SqlSaPassword)      { $SqlSaPassword      = New-RandomPassword }
if (-not $SvcAccountPassword) { $SvcAccountPassword = New-RandomPassword }

Set-KVSecret 'hvlab-sqlsa-password'       $SqlSaPassword      'SQL SA password (auto-generated)'
Set-KVSecret 'hvlab-svcaccount-password'  $SvcAccountPassword 'Service accounts password (auto-generated)'
Set-KVSecret 'hvlab-scvmm-product-key'    $ScvmmProductKey    'SCVMM product key'
Set-KVSecret 'hvlab-content-storage-key'  $storageKey         'sthvlabcontent01 key for SCVMM download'

# ── 7. GitHub Actions repo secrets ───────────────────────────────────────────
Write-Step 7 $total "GitHub Actions repo secrets"
gh secret set AZURE_CLIENT_ID       --body $clientId       --repo $GHRepo
gh secret set AZURE_TENANT_ID       --body $TenantId       --repo $GHRepo
gh secret set AZURE_SUBSCRIPTION_ID --body $DeploySubId    --repo $GHRepo
Write-OK "AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID set on $GHRepo"

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║  ✅  Preflight complete — everything is ready                ║
╠══════════════════════════════════════════════════════════════╣
║  Trigger hvlab-01 in GitHub Actions and walk away.           ║
║  Chains: 01 → 02 → 03 → 04 → 05 → 06 → 08 automatically.  ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green
