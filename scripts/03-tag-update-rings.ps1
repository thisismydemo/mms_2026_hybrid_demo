<#
.SYNOPSIS
    Tags machines with UpdateRing values for dynamic scoping in Azure Update Manager.

.DESCRIPTION
    Applies UpdateRing tags to Azure VMs and Arc-enabled servers so they are
    automatically picked up by maintenance configurations using dynamic scopes.

.PARAMETER SubscriptionId
    Azure subscription ID.

.PARAMETER ResourceGroupName
    Resource group containing the machines.

.PARAMETER Ring
    Update ring name. Defaults to Ring1.

.EXAMPLE
    .\03-tag-update-rings.ps1 -SubscriptionId "00000000-..." -ResourceGroupName "rg-hybrid-demo" -Ring "Ring1"
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $SubscriptionId,

    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [string] $Ring = 'Ring1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step    { param ([string] $M) Write-Host "`n==> $M" -ForegroundColor Cyan }
function Write-Success { param ([string] $M) Write-Host "    [OK] $M" -ForegroundColor Green }

Write-Step "Setting subscription context"
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Failed to set subscription." }

# Tag Azure VMs
Write-Step "Tagging Azure VMs with UpdateRing=$Ring"
$vms = az vm list --resource-group $ResourceGroupName --query "[].id" --output tsv 2>$null
foreach ($vmId in $vms) {
    if ($vmId) {
        az tag update --resource-id $vmId --operation Merge --tags "UpdateRing=$Ring" --output none
        $vmName = ($vmId -split '/')[-1]
        Write-Success "Tagged VM: $vmName"
    }
}

# Tag Arc-enabled servers
Write-Step "Tagging Arc-enabled servers with UpdateRing=$Ring"
$arcServers = az connectedmachine list --resource-group $ResourceGroupName --query "[].id" --output tsv 2>$null
foreach ($arcId in $arcServers) {
    if ($arcId) {
        az tag update --resource-id $arcId --operation Merge --tags "UpdateRing=$Ring" --output none
        $arcName = ($arcId -split '/')[-1]
        Write-Success "Tagged Arc server: $arcName"
    }
}

Write-Step "Tagging complete"
Write-Host "Machines tagged with UpdateRing=$Ring will be picked up by maintenance configurations with matching dynamic scopes."
