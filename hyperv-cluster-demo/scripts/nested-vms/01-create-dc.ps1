##############################################################################
# 01-create-dc.ps1  — Create hvdc01 (replica DC for azrl.mgmt)
# Runs on: self-hosted runner (hvlab-host) inside vm-hvlab-host01-eus-01
# Note: A replica DC is needed so cluster nodes have local Kerberos/DNS
#       without depending on WAN connectivity to 10.250.1.36/.37.
##############################################################################

param(
    [string]$VMName        = 'hvdc01',
    [string]$ISOPath       = 'D:\HyperVStorage\ISOs\WS2022.iso',
    [string]$VHDPath       = 'D:\HyperVStorage\VMs\hvdc01\hvdc01-os.vhdx',
    [int]   $VHDSizeGB     = 80,
    [int]   $vCPUs         = 2,
    [int]   $MemoryGB      = 8,
    [string]$MgmtIP        = '172.16.10.10',
    [string]$MgmtPrefixLen = '24',
    [string]$MgmtGateway   = '172.16.10.1',
    [string]$DomainFqdn    = 'azrl.mgmt',
    [string]$ReplicationSource = '10.250.1.36'   # existing DC1
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Creating $VMName ===" -ForegroundColor Cyan

New-Item -ItemType Directory -Path (Split-Path $VHDPath) -Force | Out-Null
New-VHD -Path $VHDPath -SizeBytes ($VHDSizeGB * 1GB) -Dynamic | Out-Null

$vm = New-VM -Name $VMName `
    -Generation 2 `
    -MemoryStartupBytes ($MemoryGB * 1GB) `
    -VHDPath $VHDPath `
    -SwitchName 'vSwitch-Mgmt'

Set-VMProcessor -VM $vm -Count $vCPUs
Set-VMMemory -VM $vm -DynamicMemoryEnabled $false
Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows

# Add External NIC for Azure VNet reachability (AD replication from .36/.37)
Add-VMNetworkAdapter -VM $vm -SwitchName 'vSwitch-External' -Name 'External'

# Boot from ISO
$dvd = Add-VMDvdDrive -VM $vm -Path $ISOPath -PassThru
Set-VMFirmware -VM $vm -BootOrder $dvd, (Get-VMHardDiskDrive -VM $vm)

# Enable MAC spoofing on External NIC (required for IP .45 range)
Get-VMNetworkAdapter -VM $vm -Name 'External' |
    Set-VMNetworkAdapter -MacAddressSpoofing On

Write-Host "VM $VMName created. Start VM and complete OS install, then run configure/05-configure-ad.ps1"
Write-Host "Post-install steps:"
Write-Host "  1. Install OS from ISO"
Write-Host "  2. Set static IP $MgmtIP/24 on Mgmt NIC, gateway $MgmtGateway"
Write-Host "  3. Set DNS to $ReplicationSource (existing DC)"
Write-Host "  4. Join domain $DomainFqdn"
Write-Host "  5. Install AD DS role, promote as additional DC (replicate from $ReplicationSource)"
Write-Host "  6. Run configure/05-configure-ad.ps1 to create OUs, service accounts, security groups"

Start-VM -VM $vm
Write-Host "VM started. Connect via Hyper-V console to complete OS setup."
