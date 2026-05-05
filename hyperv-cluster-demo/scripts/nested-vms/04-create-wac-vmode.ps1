##############################################################################
# 04-create-wac-vmode.ps1  — Create hvwac01 (WAC Virtualization Mode server)
#
# CRITICAL: Must use Windows Server 2025. WS2022 is NOT supported.
# WAC vmode is a DIFFERENT product from WAC Administration Mode.
# Download: https://aka.ms/WACDownloadvMode
##############################################################################

param(
    [string]$VMName   = 'hvwac01',
    [string]$ISOPath  = 'D:\HyperVStorage\ISOs\WS2025.iso',  # WS2025 REQUIRED
    [string]$VHDBase  = 'D:\HyperVStorage\VMs\hvwac01',
    [int]   $vCPUs    = 4,
    [int]   $MemoryGB = 16,
    [int]   $OSDiskGB = 80,
    [string]$MgmtIP   = '172.16.10.30',
    # External IP — secondary IP on Azure NIC, Azure-routable from on-prem via BGP
    [string]$ExternalIP = '10.250.1.46'
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Creating $VMName (WAC Virtualization Mode — WS2025) ===" -ForegroundColor Cyan
Write-Host "⚠️  WS2025 ISO required. WS2022 will NOT work for WAC vmode." -ForegroundColor Yellow

if (-not (Test-Path $ISOPath)) {
    Write-Warning "ISO not found at $ISOPath. Download WS2025 evaluation ISO first."
    Write-Warning "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025"
}

New-Item -ItemType Directory -Path $VHDBase -Force | Out-Null
$osDisk = Join-Path $VHDBase 'hvwac01-os.vhdx'
New-VHD -Path $osDisk -SizeBytes ($OSDiskGB * 1GB) -Dynamic | Out-Null

$vm = New-VM -Name $VMName `
    -Generation 2 `
    -MemoryStartupBytes ($MemoryGB * 1GB) `
    -VHDPath $osDisk `
    -SwitchName 'vSwitch-External'   # Primary NIC on External — gets 10.250.1.46

Set-VMProcessor -VM $vm -Count $vCPUs
Set-VMMemory    -VM $vm -DynamicMemoryEnabled $false
Set-VMFirmware  -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows

# Mgmt NIC (172.16.10.30) for internal access
Add-VMNetworkAdapter -VM $vm -SwitchName 'vSwitch-Mgmt' -Name 'Mgmt'

# Boot from ISO
$dvd = Add-VMDvdDrive -VM $vm -Path $ISOPath -PassThru
Set-VMFirmware -VM $vm -BootOrder $dvd, (Get-VMHardDiskDrive -VM $vm | Select-Object -First 1)

Start-VM -VM $vm

Write-Host @"
✅ $VMName created and started.

Post-install (MUST be WS2025):
  1. Install WS2025 from ISO (verify version in winver — must say Windows Server 2025)
  2. External NIC: static IP $ExternalIP/24, gateway 10.250.1.1, DNS 10.250.1.36
  3. Mgmt NIC: $MgmtIP/24
  4. Join domain azrl.mgmt
  5. Run configure/04-configure-wac-vmode.ps1 to:
     - Install Visual C++ Redistributable prereq
     - Download installer from https://aka.ms/WACDownloadvMode
     - Install WAC vmode with PostgreSQL
     - Add cluster hosts as managed nodes

Access URL after install: https://$ExternalIP (accessible from VNet + on-prem via BGP)
"@
