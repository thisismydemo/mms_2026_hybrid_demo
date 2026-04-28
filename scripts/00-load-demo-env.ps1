<#
.SYNOPSIS
    Loads demo environment variables from env.json into the current session.

.DESCRIPTION
    Reads env.json from the repo root, validates that required TODO placeholders
    have been replaced, and exports:
      $Global:DemoEnv  - full configuration object
      $Global:DemoTags - hashtable of required resource tags (see STANDARDS.md)

.EXAMPLE
    . .\scripts\00-load-demo-env.ps1

    # Access config values:
    $DemoEnv.azure.subscriptionId
    $DemoEnv.resourceGroup             # rg-hyb-mms26-demo-eus-01
    $DemoEnv.maintenance.ring1         # mc-hyb-mms26-demo-eus-01

    # Apply tags to any resource:
    New-AzResourceGroup -Name $rg -Location $loc -Tag $Global:DemoTags
    Update-AzTag -ResourceId $id -Tag $Global:DemoTags -Operation Merge

    # Run a demo prep script:
    .\scripts\01-prepare-demo-environment.ps1 `
        -SubscriptionId $DemoEnv.azure.subscriptionId `
        -ResourceGroupName $DemoEnv.resourceGroup

    .\scripts\02-create-maintenance-configurations.ps1 `
        -SubscriptionId $DemoEnv.azure.subscriptionId `
        -ResourceGroupName $DemoEnv.resourceGroup `
        -Ring1Name $DemoEnv.maintenance.ring1 `
        -Ring2Name $DemoEnv.maintenance.ring2 `
        -Location $DemoEnv.azure.location

    .\scripts\05-validate-hotpatch-readiness.ps1 `
        -MachineName $DemoEnv.hotpatch.machineName `
        -ResourceGroupName $DemoEnv.hotpatch.resourceGroup

.NOTES
    Demo    : The Hybrid Update Blues
    Session : MMS MOA 2026
    Owner   : Kristopher Turner
    Repo    : https://github.com/thisismydemo/mms_2026_hybrid_demo
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envFile = Join-Path $PSScriptRoot '..\env.json'

if (-not (Test-Path $envFile)) {
    Write-Host @"
[ERROR] env.json not found.

  1. Copy env.sample.json to env.json in the repo root.
  2. Fill in all values marked with TODO.
  3. Re-run this script.

"@ -ForegroundColor Red
    return
}

$DemoEnv = Get-Content $envFile -Raw | ConvertFrom-Json

# Validate: warn if any TODO placeholders remain
$raw = Get-Content $envFile -Raw
if ($raw -match '"TODO:') {
    $lines = (Get-Content $envFile) | Select-String 'TODO:'
    Write-Host "`n[WARN] env.json still has unfilled TODO values:" -ForegroundColor Yellow
    $lines | ForEach-Object { Write-Host "    Line $($_.LineNumber): $($_.Line.Trim())" -ForegroundColor Yellow }
    Write-Host ""
}

# Export full config as global
$Global:DemoEnv = $DemoEnv

# Build required tag hashtable from the tags section in env.json
# Use $Global:DemoTags wherever you create or update Azure resources.
$Global:DemoTags = @{}
if ($DemoEnv.tags) {
    $DemoEnv.tags.PSObject.Properties | ForEach-Object {
        $Global:DemoTags[$_.Name] = $_.Value
    }
}

Write-Host "`n[OK] Demo environment loaded" -ForegroundColor Green
Write-Host "     Demo          : $($DemoEnv.meta.demoName)"
Write-Host "     Conference    : $($DemoEnv.meta.conference)"
Write-Host "     Subscription  : $($DemoEnv.azure.subscriptionId)"
Write-Host "     Location      : $($DemoEnv.azure.location)"
Write-Host "     Resource Group: $($DemoEnv.resourceGroup)"
Write-Host "     Tags loaded   : $($Global:DemoTags.Count) required tags in `$Global:DemoTags"
Write-Host ""
Write-Host "Use `$DemoEnv.<section>.<property> for config values." -ForegroundColor Cyan
Write-Host "Use `$Global:DemoTags hashtable to tag any Azure resource." -ForegroundColor Cyan
Write-Host "See STANDARDS.md for naming conventions and tagging requirements."
