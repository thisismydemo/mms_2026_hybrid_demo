##############################################################################
# 03-create-cluster-nodes.ps1  - Create hvnode01 through hvnode04 unattended
##############################################################################

param(
    [string]$StorageRoot       = '',
    [string]$ISOPath           = '',
    [string]$BootstrapPassword = '',
    [int]$NodeCount            = 4,
    [int]$vCPUs                = 16,
    [int]$MemoryGB             = 64,
    [int]$OSDiskGB             = 80,
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

$bootstrapCredential = New-HVLabBootstrapCredential -SecretValue $BootstrapPassword -VaultName $KVName -SubscriptionId $KVSubscription
$nodeConfig = @(
    @{ Name = 'hvnode01'; MgmtIP = '172.16.10.21'; MigIP = '172.16.20.21'; StorIP1 = '172.16.30.21'; StorIP2 = '172.16.30.25'; HbIP = '172.16.40.21' },
    @{ Name = 'hvnode02'; MgmtIP = '172.16.10.22'; MigIP = '172.16.20.22'; StorIP1 = '172.16.30.22'; StorIP2 = '172.16.30.26'; HbIP = '172.16.40.22' },
    @{ Name = 'hvnode03'; MgmtIP = '172.16.10.23'; MigIP = '172.16.20.23'; StorIP1 = '172.16.30.23'; StorIP2 = '172.16.30.27'; HbIP = '172.16.40.23' },
    @{ Name = 'hvnode04'; MgmtIP = '172.16.10.24'; MigIP = '172.16.20.24'; StorIP1 = '172.16.30.24'; StorIP2 = '172.16.30.28'; HbIP = '172.16.40.24' }
) | Select-Object -First $NodeCount

foreach ($node in $nodeConfig) {
    Write-Host "=== Creating $($node.Name) ===" -ForegroundColor Cyan

    $vmPath = Resolve-HVLabStoragePath -StorageRoot $storageRoot -ChildPath "VMs\$($node.Name)"
    $osDisk = Join-Path $vmPath "$($node.Name)-os.vhdx"

    New-HVLabWindowsVhd -IsoPath $ISOPath -VhdPath $osDisk -SizeGB $OSDiskGB -ComputerName $node.Name -AdminPassword ($bootstrapCredential.GetNetworkCredential().Password) | Out-Null

    New-HVLabVm -Name $node.Name -OSVhdPath $osDisk -VmPath $vmPath -MemoryGB $MemoryGB -ProcessorCount $vCPUs -ExposeVirtualizationExtensions -AdapterDefinitions @(
        @{ Name = 'Mgmt'; SwitchName = 'vSwitch-Mgmt' },
        @{ Name = 'Migration'; SwitchName = 'vSwitch-Migration' },
        @{ Name = 'Storage1'; SwitchName = 'vSwitch-Storage' },
        @{ Name = 'Storage2'; SwitchName = 'vSwitch-Storage' },
        @{ Name = 'Heartbeat'; SwitchName = 'vSwitch-Heartbeat' },
        @{ Name = 'Workload'; SwitchName = 'vSwitch-Workload'; EnableMacAddressSpoofing = $true }
    ) | Out-Null

    Initialize-HVLabGuestNetwork -VMName $node.Name -Credential $bootstrapCredential -AdapterConfigurations @(
        @{ Name = 'Mgmt'; GuestName = 'Mgmt'; IPAddress = $node.MgmtIP; PrefixLength = 24; Gateway = '172.16.10.1'; DnsServers = @($MgmtDnsServer) },
        @{ Name = 'Migration'; GuestName = 'Migration'; IPAddress = $node.MigIP; PrefixLength = 24; Gateway = ''; DnsServers = @() },
        @{ Name = 'Storage1'; GuestName = 'Storage1'; IPAddress = $node.StorIP1; PrefixLength = 24; Gateway = ''; DnsServers = @() },
        @{ Name = 'Storage2'; GuestName = 'Storage2'; IPAddress = $node.StorIP2; PrefixLength = 24; Gateway = ''; DnsServers = @() },
        @{ Name = 'Heartbeat'; GuestName = 'Heartbeat'; IPAddress = $node.HbIP; PrefixLength = 24; Gateway = ''; DnsServers = @() },
        @{ Name = 'Workload'; GuestName = 'Workload'; IPAddress = ''; PrefixLength = 0; Gateway = ''; DnsServers = @() }
    )

    $domainCredential = New-Object System.Management.Automation.PSCredential(
        "$DomainJoinUser@$DomainFqdn",
        $bootstrapCredential.Password
    )

    Join-HVLabGuestToDomain -VMName $node.Name -LocalCredential $bootstrapCredential -DomainFqdn $DomainFqdn -DomainCredential $domainCredential -DnsServers @($MgmtDnsServer)

    Write-Host "  Mgmt: $($node.MgmtIP)/24  Migration: $($node.MigIP)/24"
    Write-Host "  Storage1: $($node.StorIP1)/24  Storage2: $($node.StorIP2)/24  Heartbeat: $($node.HbIP)/24"
}

Write-Host "All cluster nodes are imaged, baseline networked, and joined to $DomainFqdn."
Write-Host "Run configure/02-configure-iscsi-initiators.ps1 and configure/03-configure-cluster.ps1 next."
