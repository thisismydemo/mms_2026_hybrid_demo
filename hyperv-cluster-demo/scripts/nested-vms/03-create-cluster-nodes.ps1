##############################################################################
# 03-create-cluster-nodes.ps1  — Create hvnode01 through hvnode04
# Each node: 16 vCPU, 64 GB RAM, 5 NICs (Mgmt/Migration/Storage/Heartbeat/Workload)
##############################################################################

param(
    [string]$ISOPath    = 'D:\HyperVStorage\ISOs\WS2022.iso',
    [string]$VHDBase    = 'D:\HyperVStorage\VMs',
    [int]   $NodeCount  = 4,
    [int]   $vCPUs      = 16,
    [int]   $MemoryGB   = 64,
    [int]   $OSDiskGB   = 80
)

$ErrorActionPreference = 'Stop'

$nodeConfig = @(
    @{ Name='hvnode01'; MgmtIP='172.16.10.21'; MigIP='172.16.20.21'; StorIP='172.16.30.21'; HbIP='172.16.40.21' },
    @{ Name='hvnode02'; MgmtIP='172.16.10.22'; MigIP='172.16.20.22'; StorIP='172.16.30.22'; HbIP='172.16.40.22' },
    @{ Name='hvnode03'; MgmtIP='172.16.10.23'; MigIP='172.16.20.23'; StorIP='172.16.30.23'; HbIP='172.16.40.23' },
    @{ Name='hvnode04'; MgmtIP='172.16.10.24'; MigIP='172.16.20.24'; StorIP='172.16.30.24'; HbIP='172.16.40.24' }
)

foreach ($node in $nodeConfig) {
    Write-Host "=== Creating $($node.Name) ===" -ForegroundColor Cyan

    $vmDir  = Join-Path $VHDBase $node.Name
    $osDisk = Join-Path $vmDir "$($node.Name)-os.vhdx"
    New-Item -ItemType Directory -Path $vmDir -Force | Out-Null
    New-VHD -Path $osDisk -SizeBytes ($OSDiskGB * 1GB) -Dynamic | Out-Null

    $vm = New-VM -Name $node.Name `
        -Generation 2 `
        -MemoryStartupBytes ($MemoryGB * 1GB) `
        -VHDPath $osDisk `
        -SwitchName 'vSwitch-Mgmt'

    Set-VMProcessor -VM $vm -Count $vCPUs -ExposeVirtualizationExtensions $true
    Set-VMMemory    -VM $vm -DynamicMemoryEnabled $false
    Set-VMFirmware  -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows

    # Additional NICs
    Add-VMNetworkAdapter -VM $vm -SwitchName 'vSwitch-Migration' -Name 'Migration'
    Add-VMNetworkAdapter -VM $vm -SwitchName 'vSwitch-Storage'   -Name 'Storage'
    Add-VMNetworkAdapter -VM $vm -SwitchName 'vSwitch-Heartbeat' -Name 'Heartbeat'
    Add-VMNetworkAdapter -VM $vm -SwitchName 'vSwitch-Workload'  -Name 'Workload'

    # Boot from ISO
    $dvd = Add-VMDvdDrive -VM $vm -Path $ISOPath -PassThru
    Set-VMFirmware -VM $vm -BootOrder $dvd, (Get-VMHardDiskDrive -VM $vm | Select-Object -First 1)

    # Enable MAC spoofing on Workload NIC (needed for nested VM traffic on Workload vSwitch)
    Get-VMNetworkAdapter -VM $vm -Name 'Workload' | Set-VMNetworkAdapter -MacAddressSpoofing On

    Start-VM -VM $vm
    Write-Host "  ✅ $($node.Name) created and started"
    Write-Host "     Mgmt: $($node.MgmtIP)/24  Migration: $($node.MigIP)/24"
    Write-Host "     Storage: $($node.StorIP)/24  Heartbeat: $($node.HbIP)/24"
}

Write-Host @"

All 4 cluster nodes created. Complete OS install on each, then:
  1. Set static IPs per node (see above)
  2. Set DNS to 172.16.10.10 (hvdc01)
  3. Join domain azrl.mgmt
  4. Run configure/01-configure-iscsi-initiators.ps1 (MPIO + iSCSI)
  5. Run configure/03-configure-cluster.ps1
"@
