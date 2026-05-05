##############################################################################
# 01-take-checkpoint.ps1  — Take DEMO-READY checkpoint on all nested VMs
#
# Run AFTER full lab configuration is complete and validated (hvlab-08).
# This creates the snapshot you restore before every demo run.
#
# Checkpoint types:
#   Standard     — saved state + memory (fastest restore, requires VM off or paused)
#   Production   — VSS-based (consistent, app-aware, VM stays running) ← we use this
#
# Production checkpoints = Application-consistent snapshots. For domain-joined
# VMs with services, these are much safer than Standard checkpoints.
##############################################################################

param(
    [string]$CheckpointName = 'DEMO-READY',
    [string[]]$VMOrder = @(
        'hvdc01',      # DC first — must be running when nodes restore
        'hviscsi01',   # iSCSI second — storage must be available for nodes
        'hvnode01','hvnode02','hvnode03','hvnode04',
        'hvwac01',
        'hvscvmm01'
    ),
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
$fullName  = "$CheckpointName ($timestamp)"

Write-Host "=== Taking checkpoint '$fullName' on all nested VMs ===" -ForegroundColor Cyan

$results = @()

foreach ($vmName in $VMOrder) {
    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Warning "VM '$vmName' not found, skipping."
        continue
    }

    # Remove any existing checkpoint with the same base name to avoid clutter
    $existing = Get-VMSnapshot -VM $vm | Where-Object { $_.Name -like "$CheckpointName*" }
    if ($existing) {
        Write-Host "  🗑️  Removing old checkpoint: $($existing.Name)" -ForegroundColor DarkGray
        if (-not $WhatIf) { $existing | Remove-VMSnapshot -IncludeAllChildSnapshots -Confirm:$false }
    }

    Write-Host "  📸 Taking checkpoint on $vmName..." -ForegroundColor Yellow
    if (-not $WhatIf) {
        # Use Production checkpoint (VSS-consistent) for running VMs
        Set-VM -Name $vmName -CheckpointType Production -ErrorAction SilentlyContinue
        Checkpoint-VM -Name $vmName -SnapshotName $fullName
        $snap = Get-VMSnapshot -VM $vm | Where-Object { $_.Name -eq $fullName }
        Write-Host "  ✅ $vmName — '$($snap.Name)' @ $($snap.CreationTime)" -ForegroundColor Green
        $results += [PSCustomObject]@{ VM=$vmName; Checkpoint=$snap.Name; Created=$snap.CreationTime }
    } else {
        Write-Host "  [WHATIF] Would checkpoint: $vmName → '$fullName'" -ForegroundColor Magenta
    }
}

# Summary
Write-Host "`n=== Checkpoint Summary ===" -ForegroundColor Cyan
$results | Format-Table VM, Checkpoint, Created -AutoSize

# Save manifest for restore script
$manifestPath = "D:\HyperVStorage\checkpoints-$($CheckpointName -replace ' ','-').json"
$results | ConvertTo-Json | Out-File -FilePath $manifestPath -Encoding utf8
Write-Host "Checkpoint manifest saved: $manifestPath"

Write-Host @"

✅ All VMs checkpointed as '$CheckpointName'.
Run scripts\demo\02-restore-checkpoint.ps1 before each demo to restore.
"@
