##############################################################################
# 01-create-dc.ps1  - Create hvdc01 and promote it as the forest root DC
# Runs on: self-hosted runner on the Hyper-V host
##############################################################################

param(
    [string]$VMName            = 'hvdc01',
    [string]$StorageRoot       = '',
    [string]$ISOPath           = '',
    [string]$BootstrapPassword = '',
    [int]$VHDSizeGB            = 80,
    [int]$vCPUs                = 2,
    [int]$MemoryGB             = 8,
    [string]$MgmtIP            = '172.16.10.10',
    [int]$MgmtPrefixLen        = 24,
    [string]$MgmtGateway       = '172.16.10.1',
    [string]$DomainFqdn        = 'azrl.mgmt',
    [string]$DomainNetBIOS     = 'AZRL',
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
$vhdPath = Join-Path $vmPath "$VMName-os.vhdx"
$bootstrapCredential = New-HVLabBootstrapCredential -SecretValue $BootstrapPassword -VaultName $KVName -SubscriptionId $KVSubscription
$hostDnsServers = Get-HVLabHostDnsServers

Write-Host "=== Creating $VMName as a replica-DC candidate ===" -ForegroundColor Cyan
Write-Host "Storage root: $storageRoot"
Write-Host "Bootstrap DNS: $($hostDnsServers -join ', ')"

New-HVLabWindowsVhd -IsoPath $ISOPath -VhdPath $vhdPath -SizeGB $VHDSizeGB -ComputerName $VMName -AdminPassword ($bootstrapCredential.GetNetworkCredential().Password) | Out-Null

New-HVLabVm -Name $VMName -OSVhdPath $vhdPath -VmPath $vmPath -MemoryGB $MemoryGB -ProcessorCount $vCPUs -AdapterDefinitions @(
    @{ Name = 'Mgmt'; SwitchName = 'vSwitch-Mgmt' }
) | Out-Null

Initialize-HVLabGuestNetwork -VMName $VMName -Credential $bootstrapCredential -AdapterConfigurations @(
    @{
        Name         = 'Mgmt'
        GuestName    = 'Mgmt'
        IPAddress    = $MgmtIP
        PrefixLength = $MgmtPrefixLen
        Gateway      = $MgmtGateway
        DnsServers   = $hostDnsServers
    }
)

Invoke-HVLabPowerShellDirect -VMName $VMName -Credential $bootstrapCredential -ArgumentList $DomainFqdn, $DomainNetBIOS, $MgmtIP, ($bootstrapCredential.GetNetworkCredential().Password) -ScriptBlock {
    param($DomainFqdn, $DomainNetBIOS, $MgmtIP, $BootstrapPassword)

    $alreadyDc = $false
    try {
        Get-Service -Name NTDS -ErrorAction Stop | Out-Null
        $alreadyDc = $true
    } catch {
    }

    if (-not $alreadyDc) {
        Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
        $safeModePassword = ConvertTo-SecureString $BootstrapPassword -AsPlainText -Force
        Install-ADDSForest \
            -DomainName $DomainFqdn \
            -DomainNetbiosName $DomainNetBIOS \
            -InstallDNS \
            -SafeModeAdministratorPassword $safeModePassword \
            -NoRebootOnCompletion:$true \
            -Force:$true
    }

    $primaryAdapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Sort-Object InterfaceIndex | Select-Object -First 1
    if ($primaryAdapter) {
        Set-DnsClientServerAddress -InterfaceAlias $primaryAdapter.Name -ServerAddresses @($MgmtIP) -ErrorAction SilentlyContinue
    }
} | Out-Null

Restart-HVLabGuest -VMName $VMName -Credential $bootstrapCredential -DelaySeconds 15 -TimeoutMinutes 30

Invoke-HVLabPowerShellDirect -VMName $VMName -Credential $bootstrapCredential -ArgumentList $MgmtIP -ScriptBlock {
    param($MgmtIP)
    $primaryAdapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Sort-Object InterfaceIndex | Select-Object -First 1
    if ($primaryAdapter) {
        Set-DnsClientServerAddress -InterfaceAlias $primaryAdapter.Name -ServerAddresses @($MgmtIP) -ErrorAction SilentlyContinue
    }
} | Out-Null

Write-Host "hvdc01 is imaged, promoted, and running as the forest root DC for $DomainFqdn."
Write-Host "Run configure/05-configure-ad.ps1 next to create OUs, service accounts, groups, and DNS settings."
