##############################################################################
# 05-create-scvmm.ps1  — Create hvscvmm01 (SCVMM 2025 + SQL Server Developer)
# SQL Server Developer Edition is FREE for dev/test workloads.
##############################################################################

param(
    [string]$VMName     = 'hvscvmm01',
    [string]$ISOPath    = 'D:\HyperVStorage\ISOs\WS2022.iso',
    [string]$VHDBase    = 'D:\HyperVStorage\VMs\hvscvmm01',
    [int]   $vCPUs      = 8,
    [int]   $MemoryGB   = 32,
    [int]   $OSDiskGB   = 80,
    [int]   $DataDiskGB = 100,   # SCVMM library + SQL data
    [string]$MgmtIP     = '172.16.10.40',
    [string]$ExternalIP = '10.250.1.47'
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Creating $VMName (SCVMM 2025 + SQL Developer) ===" -ForegroundColor Cyan

New-Item -ItemType Directory -Path $VHDBase -Force | Out-Null

$osDisk   = Join-Path $VHDBase 'hvscvmm01-os.vhdx'
$dataDisk = Join-Path $VHDBase 'hvscvmm01-data.vhdx'
New-VHD -Path $osDisk   -SizeBytes ($OSDiskGB   * 1GB) -Dynamic | Out-Null
New-VHD -Path $dataDisk -SizeBytes ($DataDiskGB * 1GB) -Dynamic | Out-Null

$vm = New-VM -Name $VMName `
    -Generation 2 `
    -MemoryStartupBytes ($MemoryGB * 1GB) `
    -VHDPath $osDisk `
    -SwitchName 'vSwitch-External'   # Primary NIC → 10.250.1.47

Set-VMProcessor -VM $vm -Count $vCPUs
Set-VMMemory    -VM $vm -DynamicMemoryEnabled $false
Set-VMFirmware  -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows

Add-VMHardDiskDrive -VM $vm -Path $dataDisk
Add-VMNetworkAdapter -VM $vm -SwitchName 'vSwitch-Mgmt' -Name 'Mgmt'

$dvd = Add-VMDvdDrive -VM $vm -Path $ISOPath -PassThru
Set-VMFirmware -VM $vm -BootOrder $dvd, (Get-VMHardDiskDrive -VM $vm | Select-Object -First 1)

Start-VM -VM $vm

Write-Host @"
✅ $VMName created and started.

Post-install:
  1. Install WS2022 from ISO
  2. External NIC: $ExternalIP/24, gateway 10.250.1.1, DNS 10.250.1.36
  3. Mgmt NIC: $MgmtIP/24
  4. Initialize D:\ drive (data disk) for SCVMM library + SQL data files
  5. Join domain azrl.mgmt
  6. Create service accounts in AD (run configure/05-configure-ad.ps1 first)
  7. Run configure/06-configure-scvmm.ps1 to:
     - Install SQL Server Developer (free for dev/test)
     - Install SCVMM 2025 management server
     - Add Hyper-V hosts and cluster hvlab-clus01
     - Configure logical networks and library

SCVMM console: RDP to $ExternalIP, open VMM console
"@
