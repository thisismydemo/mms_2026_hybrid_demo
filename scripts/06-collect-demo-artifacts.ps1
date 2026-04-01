<#
.SYNOPSIS
    Collects demo artifacts for fallback use during the session.

.DESCRIPTION
    Gathers resource listings, Arc server status, maintenance configs,
    and update compliance into a local artifacts folder.

.PARAMETER SubscriptionId
    Azure subscription ID.

.PARAMETER ResourceGroupName
    Resource group containing demo resources.

.PARAMETER OutputPath
    Local folder for artifacts. Defaults to .\artifacts.

.EXAMPLE
    .\06-collect-demo-artifacts.ps1 -SubscriptionId "00000000-..." -ResourceGroupName "rg-hybrid-demo"
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $SubscriptionId,

    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [string] $OutputPath = '.\artifacts'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step    { param ([string] $M) Write-Host "`n==> $M" -ForegroundColor Cyan }
function Write-Success { param ([string] $M) Write-Host "    [OK] $M" -ForegroundColor Green }

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Step "Setting subscription context"
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Failed to set subscription." }

Write-Step "Collecting resource group inventory"
az resource list --resource-group $ResourceGroupName --output json |
    Set-Content -Path (Join-Path $OutputPath "resource-list.json")
Write-Success "Resource list saved"

Write-Step "Collecting Arc-enabled servers"
$arcJson = az connectedmachine list --resource-group $ResourceGroupName --output json 2>$null
if ($arcJson) {
    $arcJson | Set-Content -Path (Join-Path $OutputPath "arc-servers.json")
    Write-Success "Arc servers saved"
} else {
    Write-Host "    No Arc servers found" -ForegroundColor Yellow
}

Write-Step "Collecting Azure VMs"
$vmJson = az vm list --resource-group $ResourceGroupName --output json 2>$null
if ($vmJson) {
    $vmJson | Set-Content -Path (Join-Path $OutputPath "azure-vms.json")
    Write-Success "Azure VMs saved"
} else {
    Write-Host "    No Azure VMs found" -ForegroundColor Yellow
}

Write-Step "Collecting maintenance configurations"
$mcJson = az maintenance configuration list --resource-group $ResourceGroupName --output json 2>$null
if ($mcJson) {
    $mcJson | Set-Content -Path (Join-Path $OutputPath "maintenance-configs.json")
    Write-Success "Maintenance configurations saved"
} else {
    Write-Host "    No maintenance configurations found" -ForegroundColor Yellow
}

Write-Step "Artifacts collected to: $OutputPath"
Get-ChildItem -Path $OutputPath | Format-Table Name, Length, LastWriteTime
