##############################################################################
# 01-create-dc.ps1  — Create hvdc01 (forest root DC for azrl.mgmt)
# Runs on: self-hosted runner (hvlab-host) inside vm-hvlab-host01-eus-01
# Note: Isolated VNet — standalone new forest, no replication from external DCs.
##############################################################################

param(
    [string]$VMName        = 'hvdc01',
    [string]$ISOPath       = 'D:\HyperVStorage\ISOs\WS2025.iso',
    [string]$VHDPath       = 'D:\HyperVStorage\VMs\hvdc01\hvdc01-os.vhdx',
    [int]   $VHDSizeGB     = 80,
    [int]   $vCPUs         = 2,
    [int]   $MemoryGB      = 8,
    [string]$MgmtIP        = '172.16.10.10',
    [string]$MgmtPrefixLen = '24',
    [string]$MgmtGateway   = '172.16.10.1',
    [string]$DomainFqdn    = 'azrl.mgmt'
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

# Boot from ISO
$dvd = Add-VMDvdDrive -VM $vm -Path $ISOPath -PassThru
Set-VMFirmware -VM $vm -BootOrder $dvd, (Get-VMHardDiskDrive -VM $vm)

Write-Host "VM $VMName created. Start VM and complete OS install, then run configure/05-configure-ad.ps1"
Write-Host "Post-install steps:"
Write-Host "  1. Install OS from ISO"
Write-Host "  2. Set static IP $MgmtIP/$MgmtPrefixLen on Mgmt NIC, gateway $MgmtGateway"
Write-Host "  3. Set DNS to 127.0.0.1 (self — will be authoritative for $DomainFqdn)"
Write-Host "  4. Install AD DS role: Install-WindowsFeature AD-Domain-Services -IncludeManagementTools"
Write-Host "  5. Promote as forest root: Install-ADDSForest -DomainName $DomainFqdn -InstallDns"
Write-Host "  6. Run configure/05-configure-ad.ps1 to create OUs, service accounts, security groups"

Start-VM -VM $vm
Write-Host "VM started. Connect via Hyper-V console to complete OS setup."
