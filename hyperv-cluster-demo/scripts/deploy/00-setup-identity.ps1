##############################################################################
# 00-setup-identity.ps1  — ONE-TIME preflight. Run this from VS Code / Claude Code.
#
# Prerequisites: az login (as yourself) to the tplabs tenant first.
#
# Source of truth: hyperv-cluster-demo/config/variables.yml
#
# What this does (fully automated, no prompts):
#   1.  Creates resource group rg-hvlab-mms26-eus-01
#   2.  Creates storage account sthvlabcontent01 + uploads SCVMM 2025 installer
#   3.  Deploys identity.bicep → managed identity mi-hvlab-deploy-eus-01
#         with GitHub Actions OIDC federated credentials (no app registration)
#   4.  Assigns roles on deployment sub (Contributor + User Access Administrator)
#   5.  Assigns Key Vault Secrets User on kv-tplabs-platform (cross-sub, rg-azrlmgmt-dev-eus-01)
#   6.  Pre-stages ALL required KV secrets (see variables.yml section 10)
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
    [string]$KVRg            = 'rg-azrlmgmt-dev-eus-01',     # actual RG — verified 2026-05
    [string]$ContentStorage  = 'sthvlabcontent01',
    [string]$ScvmmSourcePath = 'E:\tmp\SCVMM_2025',
    [string]$GHRepo          = 'thisismydemo/mms_2026_hybrid_demo',
    [string]$ScvmmProductKey = 'EVAL'
)

$ErrorActionPreference = 'Stop'
$BicepFile = Join-Path $PSScriptRoot '..\..\bicep\identity.bicep'

function Write-Step { param([int]$n,[int]$total,[string]$msg)
    Write-Host "`n[$n/$total] $msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$msg) Write-Host "  ✅ $msg" -ForegroundColor Green }
function Write-Skip { param([string]$msg) Write-Host "  ⏭  $msg" -ForegroundColor DarkGray }
function Write-Warn { param([string]$msg) Write-Host "  ⚠️  $msg" -ForegroundColor Yellow }

function New-RandomPassword {
    # Alphanumeric + hyphen/underscore — no shell metacharacters (& $ ' break az.cmd on Windows)
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_'
    -join ((1..32) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

function Set-KVSecret {
    param([string]$Name, [string]$Value, [string]$Description)
    $existing = az keyvault secret show --vault-name $KVName --subscription $TplabsSubId `
        --name $Name --query name -o tsv 2>$null
    if ($existing) { Write-Skip "$Name already exists"; return }
    # Use --file to bypass az.cmd argument parsing issues with special characters
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $Value, (New-Object System.Text.UTF8Encoding $false))
        az keyvault secret set --vault-name $KVName --subscription $TplabsSubId `
            --name $Name --file $tmp --encoding ascii --output none
    } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
    Write-OK "$Name set ($Description)"
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
    --tags environment=lab workload=hvlab-mms26 owner=kristopherjturner `
           cost_center=tplabs-demo demo_event=mms-moa-2026 --output none
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
$deployJson = az deployment sub create `
    --subscription $DeploySubId --location $Location `
    --template-file $BicepFile --parameters location=$Location `
    --name "hvlab-identity-setup" --output json
if ($LASTEXITCODE -ne 0) { Write-Error "Bicep deployment failed"; exit 1 }
$deployOut   = $deployJson | ConvertFrom-Json
$clientId    = $deployOut.properties.outputs.identityClientId.value
$principalId = $deployOut.properties.outputs.identityPrincipalId.value
Write-OK "mi-hvlab-deploy-eus-01 | clientId: $clientId"

# ── 4. KV Secrets User on kv-tplabs-platform (cross-sub) ─────────────────────
Write-Step 4 $total "Key Vault role assignment (cross-subscription: $KVRg)"
$kvId = az keyvault show --name $KVName --resource-group $KVRg `
    --subscription $TplabsSubId --query id -o tsv
if (-not $kvId) { Write-Error "Could not resolve Key Vault ID for $KVName in $KVRg"; exit 1 }
$existingRole = az role assignment list --role "Key Vault Secrets User" `
    --assignee $principalId --scope $kvId --subscription $TplabsSubId --query "[0].id" -o tsv 2>$null
if ($existingRole) {
    Write-Skip "Key Vault Secrets User already assigned on $KVName"
} else {
    az role assignment create --role "Key Vault Secrets User" `
        --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
        --scope $kvId --subscription $TplabsSubId --output none
    Write-OK "Key Vault Secrets User assigned on $KVName"
}

# ── 5. Storage Blob Data Reader for VM MI — done in workflow 01 ──────────────

# ── 6. Pre-stage ALL required KV secrets (variables.yml section 10) ──────────
Write-Step 6 $total "Pre-staging KV secrets (variables.yml section 10)"

# Auto-generated passwords for service accounts
Set-KVSecret 'hvlab-host01-admin-password'  (New-RandomPassword)  'Host VM local admin'
Set-KVSecret 'hvwac01-pg-password'          (New-RandomPassword)  'WAC vmode PostgreSQL'
Set-KVSecret 'svc-hvlab-deploy-password'    (New-RandomPassword)  'svc-hvlab-deploy AD account'
Set-KVSecret 'svc-scvmm-svc-password'       (New-RandomPassword)  'svc-scvmm-svc AD account'
Set-KVSecret 'svc-scvmm-agent-password'     (New-RandomPassword)  'svc-scvmm-agent AD account'
Set-KVSecret 'svc-scvmm-runas-password'     (New-RandomPassword)  'svc-scvmm-runas AD account'
Set-KVSecret 'svc-sql-scvmm-password'       (New-RandomPassword)  'svc-sql-scvmm AD account'
Set-KVSecret 'svc-wac-gateway-password'     (New-RandomPassword)  'svc-wac-gateway AD account'

# Storage key for SCVMM installer download during bootstrap
Set-KVSecret 'hvlab-content-storage-key'    $storageKey           'sthvlabcontent01 access key'

# SCVMM product key
Set-KVSecret 'hvlab-scvmm-product-key'      $ScvmmProductKey      'SCVMM 2025 product key'

# GitHub runner registration token — generate via API
Write-Host "  Generating GitHub Actions runner registration token..." -ForegroundColor DarkGray
$runnerToken = $null
try {
    $apiResponse = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$GHRepo/actions/runners/registration-token" `
        -Method POST `
        -Headers @{ Authorization = "Bearer $($env:GH_TOKEN)"; Accept = "application/vnd.github+json" }
    $runnerToken = $apiResponse.token
} catch {
    Write-Warn "Could not auto-generate runner token (PAT may lack admin:repo scope). Set hvlab-github-runner-token manually."
}
if ($runnerToken) {
    Set-KVSecret 'hvlab-github-runner-token' $runnerToken 'GitHub Actions self-hosted runner registration token'
}

# ── 7. GitHub Actions repo secrets ───────────────────────────────────────────
Write-Step 7 $total "GitHub Actions repo secrets (AZURE_CLIENT_ID / TENANT_ID / SUBSCRIPTION_ID)"
$ghErrors = @()
foreach ($secret in @(
    @{ name = 'AZURE_CLIENT_ID';       value = $clientId    },
    @{ name = 'AZURE_TENANT_ID';       value = $TenantId    },
    @{ name = 'AZURE_SUBSCRIPTION_ID'; value = $DeploySubId }
)) {
    $out = gh secret set $secret.name --body $secret.value --repo $GHRepo 2>&1
    if ($LASTEXITCODE -ne 0) { $ghErrors += "$($secret.name): $out" }
    else { Write-OK "$($secret.name) set" }
}
if ($ghErrors.Count -gt 0) {
    Write-Warn "GitHub secret(s) failed — PAT needs 'Secrets: read and write' permission:"
    $ghErrors | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    Write-Warn "Go to github.com → Settings → Developer settings → Personal access tokens and update GH_TOKEN."
}

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║  ✅  Preflight complete — everything is ready                ║
╠══════════════════════════════════════════════════════════════╣
║  Trigger hvlab-01 in GitHub Actions and walk away.           ║
║  Chains: 01 → 02 → 03 → 04 → 05 → 06 → 08 automatically.  ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green
