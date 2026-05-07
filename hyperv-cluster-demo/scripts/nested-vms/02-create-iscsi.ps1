##############################################################################
# 02-create-iscsi.ps1  - Create hviscsi01 with an unattended OS baseline
##############################################################################

param(
    [string]$VMName            = 'hviscsi01',
    [string]$StorageRoot       = '',
    [string]$ISOPath           = '',
    [string]$BootstrapPassword = '',
    [int]$vCPUs                = 4,
    [int]$MemoryGB             = 16,
    [int]$OSDiskGB             = 80,
    [int[]]$DataDiskGB         = @(2, 500, 500, 500),
    [string]$StorageIP1        = '172.16.30.10',
    [string]$StorageIP2        = '172.16.30.11',
    [string]$MgmtIP            = '172.16.10.15',
    [int]$MgmtPrefixLen        = 24,
    [string]$MgmtGateway       = '172.16.10.1',
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
$bootstrapCredential = New-HVLabBootstrapCredential -SecretValue $BootstrapPassword -VaultName $KVName -SubscriptionId $KVSubscription

$lunNames = @('quorum', 'csv01', 'csv02', 'csv03-templates')
$dataVhdPaths = @()
for ($i = 0; $i -lt $DataDiskGB.Count; $i++) {
    $dataVhdPath = Join-Path $vmPath ("{0}-data{1}-{2}.vhdx" -f $VMName, ($i + 1), $lunNames[$i])
    if (-not (Test-Path $dataVhdPath)) {
        New-VHD -Path $dataVhdPath -SizeBytes ($DataDiskGB[$i] * 1GB) -Dynamic | Out-Null
    }
    $dataVhdPaths += $dataVhdPath
}

Write-Host "=== Creating $VMName ===" -ForegroundColor Cyan
Write-Host "Storage root: $storageRoot"

New-HVLabWindowsVhd -IsoPath $ISOPath -VhdPath $osDisk -SizeGB $OSDiskGB -ComputerName $VMName -AdminPassword ($bootstrapCredential.GetNetworkCredential().Password) | Out-Null

New-HVLabVm -Name $VMName -OSVhdPath $osDisk -VmPath $vmPath -MemoryGB $MemoryGB -ProcessorCount $vCPUs -AdapterDefinitions @(
    @{ Name = 'Storage1'; SwitchName = 'vSwitch-Storage' },
    @{ Name = 'Storage2'; SwitchName = 'vSwitch-Storage' },
    @{ Name = 'Mgmt'; SwitchName = 'vSwitch-Mgmt' }
) -DataVhdPaths $dataVhdPaths | Out-Null

Initialize-HVLabGuestNetwork -VMName $VMName -Credential $bootstrapCredential -AdapterConfigurations @(
    @{ Name = 'Storage1'; GuestName = 'Storage1'; IPAddress = $StorageIP1; PrefixLength = 24; Gateway = ''; DnsServers = @() },
    @{ Name = 'Storage2'; GuestName = 'Storage2'; IPAddress = $StorageIP2; PrefixLength = 24; Gateway = ''; DnsServers = @() },
    @{ Name = 'Mgmt'; GuestName = 'Mgmt'; IPAddress = $MgmtIP; PrefixLength = $MgmtPrefixLen; Gateway = $MgmtGateway; DnsServers = @($MgmtDnsServer) }
)

$domainCredential = New-Object System.Management.Automation.PSCredential(
    "$DomainJoinUser@$DomainFqdn",
    $bootstrapCredential.Password
)

Join-HVLabGuestToDomain -VMName $VMName -LocalCredential $bootstrapCredential -DomainFqdn $DomainFqdn -DomainCredential $domainCredential -DnsServers @($MgmtDnsServer)

Write-Host "hviscsi01 is imaged, booted, and joined to $DomainFqdn."
Write-Host "Run configure/01-configure-iscsi.ps1 to initialize disks and publish the LUNs."
