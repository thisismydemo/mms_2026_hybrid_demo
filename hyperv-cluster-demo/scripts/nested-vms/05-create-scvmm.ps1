##############################################################################
# 05-create-scvmm.ps1  - Create hvscvmm01 unattended on WS2025
##############################################################################

param(
    [string]$VMName            = 'hvscvmm01',
    [string]$StorageRoot       = '',
    [string]$ISOPath           = '',
    [string]$BootstrapPassword = '',
    [int]$vCPUs                = 8,
    [int]$MemoryGB             = 32,
    [int]$OSDiskGB             = 80,
    [int]$DataDiskGB           = 100,
    [string]$MgmtIP            = '172.16.10.40',
    [int]$MgmtPrefixLen        = 24,
    [string]$ExternalIP        = '10.250.2.7',
    [int]$ExternalPrefixLen    = 27,
    [string]$ExternalGateway   = '10.250.2.1',
    [string]$MgmtDnsServer     = '172.16.10.10',
    [string]$DomainFqdn        = 'azrl.mgmt',
    [string]$DomainJoinUser    = 'Administrator',
    [string]$KVName            = 'kv-tplabs-platform',
    [string]$KVSubscription    = '2caa0b8a-a1d6-4f0c-8c03-861787b8315c'
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\common\HVLab.Automation.psm1'
Import-Module $modulePath -Force

$storageRoot = Get-HVLabStorageRoot -PreferredRoot $StorageRoot
if (-not $ISOPath) {
    $ISOPath = Resolve-HVLabStoragePath -StorageRoot $storageRoot -ChildPath 'ISOs\WS2025.iso'
}

$vmPath = Resolve-HVLabStoragePath -StorageRoot $storageRoot -ChildPath "VMs\$VMName"
$osDisk = Join-Path $vmPath "$VMName-os.vhdx"
$dataDisk = Join-Path $vmPath "$VMName-data.vhdx"
if (-not (Test-Path $dataDisk)) {
    New-VHD -Path $dataDisk -SizeBytes ($DataDiskGB * 1GB) -Dynamic | Out-Null
}

$bootstrapCredential = New-HVLabBootstrapCredential -SecretValue $BootstrapPassword -VaultName $KVName -SubscriptionId $KVSubscription

Write-Host "=== Creating $VMName (SCVMM 2025 + SQL Developer) ===" -ForegroundColor Cyan

New-HVLabWindowsVhd -IsoPath $ISOPath -VhdPath $osDisk -SizeGB $OSDiskGB -ComputerName $VMName -AdminPassword ($bootstrapCredential.GetNetworkCredential().Password) | Out-Null

New-HVLabVm -Name $VMName -OSVhdPath $osDisk -VmPath $vmPath -MemoryGB $MemoryGB -ProcessorCount $vCPUs -AdapterDefinitions @(
    @{ Name = 'External'; SwitchName = 'vSwitch-External' },
    @{ Name = 'Mgmt'; SwitchName = 'vSwitch-Mgmt' }
) -DataVhdPaths @($dataDisk) | Out-Null

Initialize-HVLabGuestNetwork -VMName $VMName -Credential $bootstrapCredential -AdapterConfigurations @(
    @{ Name = 'External'; GuestName = 'External'; IPAddress = $ExternalIP; PrefixLength = $ExternalPrefixLen; Gateway = $ExternalGateway; DnsServers = @($MgmtDnsServer) },
    @{ Name = 'Mgmt'; GuestName = 'Mgmt'; IPAddress = $MgmtIP; PrefixLength = $MgmtPrefixLen; Gateway = ''; DnsServers = @($MgmtDnsServer) }
)

$domainCredential = New-Object System.Management.Automation.PSCredential(
    "$DomainJoinUser@$DomainFqdn",
    $bootstrapCredential.Password
)

Join-HVLabGuestToDomain -VMName $VMName -LocalCredential $bootstrapCredential -DomainFqdn $DomainFqdn -DomainCredential $domainCredential -DnsServers @($MgmtDnsServer)

Write-Host "hvscvmm01 is imaged, booted, and joined to $DomainFqdn."
Write-Host "Run configure/06-configure-scvmm.ps1 next."
