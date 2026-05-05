##############################################################################
# 04-bootstrap-phase1.ps1
# PHASE 1 — Install Windows features required for Hyper-V host.
# Run via: az vm run-command invoke (from workflow 02, step "Phase 1")
# The VM WILL REBOOT at the end of this script.
# Workflow 02 waits 5 minutes then runs 05-bootstrap-phase2.ps1.
##############################################################################

$ErrorActionPreference = 'Stop'
$logFile = 'C:\hvlab-bootstrap-phase1.log'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $logFile -Value $line
    Write-Host $line
}

Write-Log "=== HV-Lab Bootstrap Phase 1 — Windows Features ==="

$features = @(
    'Hyper-V',
    'Hyper-V-PowerShell',
    'Failover-Clustering',
    'RSAT-Clustering',
    'RSAT-Clustering-PowerShell',
    'RSAT-Clustering-Mgmt',
    'RSAT-AD-PowerShell',
    'RSAT-AD-Tools',
    'FS-iSCSITarget-Server',
    'iSCSI-Software-Initiator',
    'Multipath-IO',
    'SNMP-Service'
)

Write-Log "Installing Windows features: $($features -join ', ')"

$result = Install-WindowsFeature -Name $features -IncludeManagementTools -IncludeAllSubFeature
Write-Log "Install result: Success=$($result.Success), RestartNeeded=$($result.RestartNeeded)"

if (-not $result.Success) {
    Write-Log "Feature installation failed. Check the log." 'ERROR'
    exit 1
}

# Schedule Phase 2 to run after reboot via a startup scheduled task
Write-Log "Creating post-reboot scheduled task for Phase 2..."

$taskScript = 'C:\hvlab-bootstrap-phase2-trigger.ps1'
Set-Content -Path $taskScript -Value @'
# Triggered by scheduled task after Phase 1 reboot
# Phase 2 will be invoked by the GitHub Actions workflow via az vm run-command
# This task just signals readiness by creating a marker file
New-Item -Path 'C:\hvlab-phase1-complete.marker' -ItemType File -Force
'@

$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File $taskScript"
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName 'HVLab-Phase1-Complete' -Action $action -Trigger $trigger `
    -RunLevel Highest -User 'SYSTEM' -Force | Out-Null

Write-Log "Phase 1 complete. Rebooting in 15 seconds..."
Start-Sleep -Seconds 15
Restart-Computer -Force
