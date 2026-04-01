<#
.SYNOPSIS
    Creates a maintenance configuration for the demo with tag-based dynamic scoping.

.DESCRIPTION
    Sets up an Azure Update Manager maintenance configuration with a monthly schedule,
    Critical + Security classifications, and a dynamic scope using UpdateRing tags.

.PARAMETER SubscriptionId
    Azure subscription ID.

.PARAMETER ResourceGroupName
    Resource group for the maintenance configuration.

.PARAMETER ConfigName
    Name for the maintenance configuration. Defaults to mc-hybrid-demo.

.PARAMETER Location
    Azure region. Defaults to eastus.

.EXAMPLE
    .\02-create-maintenance-configurations.ps1 -SubscriptionId "00000000-..." -ResourceGroupName "rg-hybrid-demo"
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $SubscriptionId,

    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [string] $ConfigName = 'mc-hybrid-demo',

    [string] $Location = 'eastus'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step    { param ([string] $M) Write-Host "`n==> $M" -ForegroundColor Cyan }
function Write-Success { param ([string] $M) Write-Host "    [OK] $M" -ForegroundColor Green }

Write-Step "Setting subscription context"
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Failed to set subscription." }

Write-Step "Creating resource group (if needed)"
az group create --name $ResourceGroupName --location $Location --output none

Write-Step "Creating maintenance configuration: $ConfigName"
az maintenance configuration create `
    --resource-group $ResourceGroupName `
    --resource-name $ConfigName `
    --location $Location `
    --maintenance-scope "InGuestPatch" `
    --install-patches-linux-parameters packageNameMasksToInclude="*" classificationsToInclude="Critical" "Security" `
    --install-patches-windows-parameters classificationsToInclude="Critical" "Security" kbNumbersToExclude="" `
    --maintenance-window-duration "03:00" `
    --maintenance-window-recur-every "Month Second Tuesday" `
    --maintenance-window-start-date-time "2026-04-14 22:00" `
    --maintenance-window-time-zone "Eastern Standard Time" `
    --reboot-setting "IfRequired" `
    --output table

if ($LASTEXITCODE -ne 0) { throw "Failed to create maintenance configuration." }
Write-Success "Maintenance configuration '$ConfigName' created"

Write-Host @"

Next steps:
  1. Add dynamic scopes with tag filters (e.g., UpdateRing = Ring1)
  2. Or assign machines statically to this configuration
  3. See docs/02-azure-update-manager.md for details
"@
