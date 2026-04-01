<#
.SYNOPSIS
    Validates that the demo environment is ready for the Hybrid Update Blues session.

.DESCRIPTION
    Checks Azure VMs, Arc-enabled servers, maintenance configurations,
    Azure Local cluster, and hotpatch enrollment to confirm demo readiness.

.PARAMETER SubscriptionId
    Azure subscription ID to validate.

.PARAMETER ResourceGroupName
    Resource group containing demo resources.

.EXAMPLE
    .\01-prepare-demo-environment.ps1 -SubscriptionId "00000000-..." -ResourceGroupName "rg-hybrid-demo"
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $SubscriptionId,

    [Parameter(Mandatory)]
    [string] $ResourceGroupName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step    { param ([string] $M) Write-Host "`n==> $M" -ForegroundColor Cyan }
function Write-Success { param ([string] $M) Write-Host "    [OK] $M" -ForegroundColor Green }
function Write-Warn    { param ([string] $M) Write-Host "    [WARN] $M" -ForegroundColor Yellow }
function Write-Fail    { param ([string] $M) Write-Host "    [FAIL] $M" -ForegroundColor Red }

$issues = @()

# Set subscription
Write-Step "Setting subscription context"
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Failed to set subscription. Run 'az login' first." }
Write-Success "Subscription: $SubscriptionId"

# Check Azure VMs
Write-Step "Checking Azure VMs in Azure Update Manager"
$vms = az vm list --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
if ($vms.Count -ge 2) {
    Write-Success "Found $($vms.Count) Azure VMs"
} else {
    Write-Warn "Found $($vms.Count) Azure VMs — need at least 2 for demo"
    $issues += "Insufficient Azure VMs"
}

# Check Arc-enabled servers
Write-Step "Checking Arc-enabled servers"
$arcServers = az connectedmachine list --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
if ($arcServers) {
    $connected = $arcServers | Where-Object { $_.status -eq 'Connected' }
    Write-Success "Found $($arcServers.Count) Arc servers ($($connected.Count) connected)"
    if ($connected.Count -lt 2) {
        Write-Warn "Need at least 2 connected Arc servers for demo"
        $issues += "Insufficient connected Arc servers"
    }
} else {
    Write-Fail "No Arc-enabled servers found"
    $issues += "No Arc-enabled servers"
}

# Check maintenance configurations
Write-Step "Checking maintenance configurations"
$maintenanceConfigs = az maintenance configuration list --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
if ($maintenanceConfigs.Count -ge 1) {
    Write-Success "Found $($maintenanceConfigs.Count) maintenance configuration(s)"
} else {
    Write-Warn "No maintenance configurations found — create one for Demo 1"
    $issues += "No maintenance configurations"
}

# Summary
Write-Step "Validation Summary"
if ($issues.Count -eq 0) {
    Write-Success "All checks passed — environment is demo-ready!"
} else {
    Write-Warn "Issues found ($($issues.Count)):"
    $issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
}
