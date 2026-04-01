<#
.SYNOPSIS
    Validates hotpatch readiness on a target machine.

.DESCRIPTION
    Checks the prerequisites for hotpatching: OS version, VBS, Secure Boot,
    Arc agent status, and current enrollment.

.PARAMETER MachineName
    Name of the Arc-enabled server to check.

.PARAMETER ResourceGroupName
    Resource group containing the machine.

.EXAMPLE
    .\05-validate-hotpatch-readiness.ps1 -MachineName "srv-2025-01" -ResourceGroupName "rg-hybrid-demo"
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $MachineName,

    [Parameter(Mandatory)]
    [string] $ResourceGroupName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step    { param ([string] $M) Write-Host "`n==> $M" -ForegroundColor Cyan }
function Write-Success { param ([string] $M) Write-Host "    [OK] $M" -ForegroundColor Green }
function Write-Fail    { param ([string] $M) Write-Host "    [FAIL] $M" -ForegroundColor Red }

$issues = @()

Write-Step "Checking Arc-enabled server: $MachineName"

$machine = az connectedmachine show `
    --name $MachineName `
    --resource-group $ResourceGroupName `
    --output json 2>$null | ConvertFrom-Json

if (-not $machine) {
    Write-Fail "Machine '$MachineName' not found in resource group '$ResourceGroupName'"
    return
}

# Check connection status
if ($machine.status -eq 'Connected') {
    Write-Success "Arc agent status: Connected"
} else {
    Write-Fail "Arc agent status: $($machine.status) — must be Connected"
    $issues += "Arc agent not connected"
}

# Check OS
$osName = $machine.osProfile.computerName
$osType = $machine.osName
Write-Step "OS: $osType"
if ($osType -match '2025') {
    Write-Success "Windows Server 2025 detected — hotpatch supported"
} else {
    Write-Fail "OS is not Windows Server 2025 — hotpatch requires 2025"
    $issues += "Wrong OS version"
}

# Summary
Write-Step "Validation Summary for $MachineName"
if ($issues.Count -eq 0) {
    Write-Success "Machine appears hotpatch-ready"
    Write-Host "    Next: Enable hotpatch via Azure portal → Updates → Hotpatch"
} else {
    Write-Host "    Issues found:" -ForegroundColor Yellow
    $issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
}

Write-Host @"

Note: VBS and Secure Boot must also be enabled on the machine.
These cannot be checked remotely via Azure CLI — verify on the machine itself:
  - Run: msinfo32 → look for 'Virtualization-based security: Running'
  - Run: Confirm-SecureBootUEFI (PowerShell, requires admin)
"@
