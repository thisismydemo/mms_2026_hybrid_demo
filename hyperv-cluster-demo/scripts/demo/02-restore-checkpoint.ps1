##############################################################################
# 02-restore-checkpoint.ps1  — Restore DEMO-READY checkpoint before each demo
#
# Restores VMs in dependency order (reverse of shutdown, forward of startup):
#   1. Restore all VMs (off state, but not started)
#   2. Start in correct dependency order: DC → iSCSI → Nodes → WAC/SCVMM
#   3. Wait for each to be healthy before starting the next
#
# Usage:
#   Before Session 1:  .\02-restore-checkpoint.ps1
#   Before Session 2:  .\02-restore-checkpoint.ps1 -CheckpointName 'PRE-DEMO-2'
##############################################################################

param(
    [string]$CheckpointName = 'DEMO-READY',
    [int]   $StartupWaitSec = 120,    # seconds to wait after starting each group
    [switch]$NoStart                  # restore only, don't start VMs
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Restoring checkpoint '$CheckpointName' ===" -ForegroundColor Cyan
Write-Host "Start time: $(Get-Date -Format 'HH:mm:ss')"

# ── Step 1: Shut down all running VMs gracefully ────────────────────────────
Write-Host "`n[1/3] Shutting down running VMs..." -ForegroundColor Yellow
$runningVMs = Get-VM | Where-Object { $_.State -eq 'Running' }
foreach ($vm in $runningVMs) {
    Write-Host "  Stopping $($vm.Name)..."
    Stop-VM -Name $vm.Name -Force -TurnOff
}
if ($runningVMs) {
    Write-Host "  Waiting 10s for VMs to stop..."
    Start-Sleep -Seconds 10
}

# ── Step 2: Restore checkpoint on all VMs ───────────────────────────────────
Write-Host "`n[2/3] Restoring checkpoints..." -ForegroundColor Yellow

$vmOrder = @('hvdc01','hviscsi01','hvnode01','hvnode02','hvnode03','hvnode04','hvwac01','hvscvmm01')
$restored = 0

foreach ($vmName in $vmOrder) {
    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if (-not $vm) { Write-Warning "$vmName not found, skipping."; continue }

    $snap = Get-VMSnapshot -VM $vm | Where-Object { $_.Name -like "$CheckpointName*" } |
            Sort-Object CreationTime -Descending | Select-Object -First 1

    if (-not $snap) {
        Write-Warning "  ⚠️  No checkpoint matching '$CheckpointName' found on $vmName"
        continue
    }

    Restore-VMSnapshot -VMSnapshot $snap -Confirm:$false
    Write-Host "  ✅ Restored $vmName → '$($snap.Name)'"
    $restored++
}

Write-Host "  Restored: $restored / $($vmOrder.Count) VMs"

if ($NoStart) {
    Write-Host "`nRestore complete (NoStart). VMs are in saved/off state."
    exit 0
}

# ── Step 3: Start VMs in dependency order ───────────────────────────────────
Write-Host "`n[3/3] Starting VMs in dependency order..." -ForegroundColor Yellow

function Start-VMAndWait {
    param([string]$Name, [int]$WaitSec, [string]$Description)
    Write-Host "  ▶️  Starting $Name ($Description)..."
    Start-VM -Name $Name
    Write-Host "  ⏳ Waiting ${WaitSec}s for services to initialize..."
    Start-Sleep -Seconds $WaitSec
    $vm = Get-VM -Name $Name
    Write-Host "  $($vm.State -eq 'Running' ? '✅' : '⚠️') $Name — $($vm.State)"
}

# DC first — everything depends on it
Start-VMAndWait -Name 'hvdc01'   -WaitSec 90  -Description 'Domain Controller — wait for AD/DNS'

# iSCSI storage — cluster nodes need it before starting
Start-VMAndWait -Name 'hviscsi01' -WaitSec 45 -Description 'iSCSI Target — wait for LUN presentation'

# Cluster nodes
foreach ($node in @('hvnode01','hvnode02','hvnode03','hvnode04')) {
    Start-VM -Name $node
    Write-Host "  ▶️  Started $node"
}
Write-Host "  ⏳ Waiting ${StartupWaitSec}s for cluster nodes..."
Start-Sleep -Seconds $StartupWaitSec

# Management servers
Start-VMAndWait -Name 'hvwac01'   -WaitSec 60 -Description 'WAC vmode — PostgreSQL startup'
Start-VMAndWait -Name 'hvscvmm01' -WaitSec 60 -Description 'SCVMM + SQL Server startup'

# ── Connectivity check ───────────────────────────────────────────────────────
Write-Host "`n=== Post-Restore Connectivity Check ===" -ForegroundColor Cyan

$checks = @(
    @{ Target='hvdc01';    Port=389;  Desc='LDAP' },
    @{ Target='hviscsi01'; Port=3260; Desc='iSCSI' },
    @{ Target='hvnode01';  Port=445;  Desc='SMB' },
    @{ Target='hvnode02';  Port=445;  Desc='SMB' },
    @{ Target='hvnode03';  Port=445;  Desc='SMB' },
    @{ Target='hvnode04';  Port=445;  Desc='SMB' },
    @{ Target='hvwac01';   Port=443;  Desc='WAC HTTPS' },
    @{ Target='hvscvmm01'; Port=8100; Desc='SCVMM Console' }
)

foreach ($check in $checks) {
    $result = Test-NetConnection -ComputerName $check.Target -Port $check.Port -WarningAction SilentlyContinue
    $icon = $result.TcpTestSucceeded ? '✅' : '❌'
    Write-Host "  $icon $($check.Target):$($check.Port) ($($check.Desc))"
}

Write-Host @"

✅ Demo environment restored to '$CheckpointName'.
Elapsed: $([int]((Get-Date) - (Get-Date)).TotalMinutes) min

Access points:
  WAC vmode:      https://10.250.1.46
  SCVMM Console:  RDP to 10.250.1.47 → open vmm.exe
  Cluster:        Failover Cluster Manager → hvlab-clus01.azrl.mgmt
"@
