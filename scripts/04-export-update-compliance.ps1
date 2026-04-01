<#
.SYNOPSIS
    Exports update compliance data using Azure Resource Graph.

.DESCRIPTION
    Runs Resource Graph queries for update compliance across Azure VMs and
    Arc-enabled servers, then exports results to CSV.

.PARAMETER SubscriptionId
    Target subscription ID.

.PARAMETER OutputPath
    Folder for CSV exports. Defaults to .\artifacts.

.EXAMPLE
    .\04-export-update-compliance.ps1 -SubscriptionId "00000000-..."
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $SubscriptionId,

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

# Query 1: Machines with pending critical updates
Write-Step "Querying machines with pending critical updates"
$query1 = @"
patchassessmentresources
| where type == 'microsoft.compute/virtualmachines/patchassessmentresults' or type == 'microsoft.hybridcompute/machines/patchassessmentresults'
| extend machineId = tostring(split(id, '/patchAssessmentResults')[0])
| extend osType = properties.osType
| extend lastAssessment = properties.lastModifiedDateTime
| extend criticalCount = properties.availablePatchCountByClassification.critical
| extend securityCount = properties.availablePatchCountByClassification.security
| project machineId, osType, lastAssessment, criticalCount, securityCount
| order by criticalCount desc
"@

$output1 = Join-Path $OutputPath "pending-critical-updates.csv"
az graph query -q $query1 --subscriptions $SubscriptionId --output table > $output1
Write-Success "Exported to $output1"

# Query 2: Machines not assessed in 7 days
Write-Step "Querying machines not assessed in 7 days"
$query2 = @"
patchassessmentresources
| where type == 'microsoft.compute/virtualmachines/patchassessmentresults' or type == 'microsoft.hybridcompute/machines/patchassessmentresults'
| extend lastAssessment = todatetime(properties.lastModifiedDateTime)
| where lastAssessment < ago(7d)
| extend machineId = tostring(split(id, '/patchAssessmentResults')[0])
| project machineId, lastAssessment
| order by lastAssessment asc
"@

$output2 = Join-Path $OutputPath "not-assessed-7-days.csv"
az graph query -q $query2 --subscriptions $SubscriptionId --output table > $output2
Write-Success "Exported to $output2"

Write-Step "Export complete"
Get-ChildItem -Path $OutputPath -Filter "*.csv" | Format-Table Name, Length, LastWriteTime
