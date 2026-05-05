##############################################################################
# 02-create-iscsi.ps1  — Create hviscsi01 (iSCSI Target Server)
# Windows Server iSCSI Target Server role is FREE and built-in — no SAN needed.
# Dual-homed on Storage vSwitch for MPIO (two paths per cluster node).
##############################################################################

param(
    [string]$VMName     = 'hviscsi01',
    [string]$ISOPath    = 'D:\HyperVStorage\ISOs\WS2022.iso',
    [string]$VHDBase    = 'D:\HyperVStorage\VMs\hviscsi01',
    [int]   $vCPUs      = 4,
    [int]   $MemoryGB   = 16,
    [int]   $OSDiskGB   = 80,
    # Data VHDs for iSCSI LUNs
    [int[]] $DataDiskGB = @(2, 500, 500, 500),   # quorum, csv01, csv02, csv03-templates
    [string]$StorageIP1 = '172.16.30.10',
    [string]$StorageIP2 = '172.16.30.11'
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Creating $VMName ===" -ForegroundColor Cyan

New-Item -ItemType Directory -Path $VHDBase -Force | Out-Null

# OS disk
$osDisk = Join-Path $VHDBase 'hviscsi01-os.vhdx'
New-VHD -Path $osDisk -SizeBytes ($OSDiskGB * 1GB) -Dynamic | Out-Null

$vm = New-VM -Name $VMName `
    -Generation 2 `
    -MemoryStartupBytes ($MemoryGB * 1GB) `
    -VHDPath $osDisk `
    -SwitchName 'vSwitch-Storage'

Set-VMProcessor -VM $vm -Count $vCPUs
Set-VMMemory -VM $vm -DynamicMemoryEnabled $false
Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows

# Second Storage NIC for MPIO path 2
Add-VMNetworkAdapter -VM $vm -SwitchName 'vSwitch-Storage' -Name 'Storage2'
# Also add Mgmt NIC for management access
Add-VMNetworkAdapter -VM $vm -SwitchName 'vSwitch-Mgmt' -Name 'Mgmt'

# Data VHDs for iSCSI LUNs
$lunNames = @('quorum','csv01','csv02','csv03-templates')
for ($i = 0; $i -lt $DataDiskGB.Count; $i++) {
    $vhdPath = Join-Path $VHDBase "hviscsi01-lun$i-$($lunNames[$i]).vhdx"
    New-VHD -Path $vhdPath -SizeBytes ($DataDiskGB[$i] * 1GB) -Dynamic | Out-Null
    Add-VMHardDiskDrive -VM $vm -Path $vhdPath
    Write-Host "  LUN $i ($($lunNames[$i])): $($DataDiskGB[$i]) GB — $vhdPath"
}

# Boot from ISO
$dvd = Add-VMDvdDrive -VM $vm -Path $ISOPath -PassThru
Set-VMFirmware -VM $vm -BootOrder $dvd, (Get-VMHardDiskDrive -VM $vm | Select-Object -First 1)

Start-VM -VM $vm

Write-Host @"
VM $VMName created and started.
Post-install:
  1. Install WS2022 from ISO
  2. NIC 1 (Storage1): $StorageIP1/24
  3. NIC 2 (Storage2): $StorageIP2/24
  4. NIC 3 (Mgmt): 172.16.10.15/24
  5. Join domain azrl.mgmt
  6. Run configure/01-configure-iscsi.ps1 to install iSCSI Target role + create LUNs
"@
