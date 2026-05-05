##############################################################################
# 05-configure-ad.ps1  — Create OUs, service accounts, and security groups
# Run from: self-hosted runner OR any domain-joined machine with AD RSAT
# Target DC: hvdc01 (replica) or 10.250.1.36 (existing DC1)
##############################################################################

param(
    [string]$DomainController = 'hvdc01',
    [string]$DomainFqdn       = 'azrl.mgmt',
    [string]$KVName           = 'kv-tplabs-platform',
    [string]$KVSubscription   = '2caa0b8a-a1d6-4f0c-8c03-861787b8315c'
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
Write-Host "=== Configuring Active Directory for HV-Lab ===" -ForegroundColor Cyan

# ─────────────────────────────────────────────────────────────────────────────
# OUs
# ─────────────────────────────────────────────────────────────────────────────
$domainDN  = "DC=$($DomainFqdn.Replace('.',',DC='))"
$baseOU    = "OU=MGMT,$domainDN"

$ous = @(
    @{ Name='Servers';         Path=$baseOU },
    @{ Name='Clusters';        Path="OU=Servers,$baseOU" },
    @{ Name='hvlab-clus01';    Path="OU=Clusters,OU=Servers,$baseOU" },
    @{ Name='hvlab-servers';   Path="OU=Servers,$baseOU" },
    @{ Name='ServiceAccounts'; Path=$baseOU },
    @{ Name='Security Groups'; Path=$baseOU }
)

foreach ($ou in $ous) {
    try {
        New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path `
            -Server $DomainController -ProtectedFromAccidentalDeletion $false
        Write-Host "  ✅ OU: $($ou.Name)"
    } catch {
        if ($_.Exception.Message -like '*already exists*') {
            Write-Host "  ⏭️  OU: $($ou.Name) already exists"
        } else { throw }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Service Accounts (passwords from Key Vault)
# ─────────────────────────────────────────────────────────────────────────────
$svcOU = "OU=ServiceAccounts,$baseOU"

$serviceAccounts = @(
    @{ SAM='svc-hvlab-deploy';  Desc='HV-Lab bootstrap and deployment account';           KVSecret='svc-hvlab-deploy-password' },
    @{ SAM='svc-scvmm-svc';     Desc='SCVMM management server service account';           KVSecret='svc-scvmm-svc-password' },
    @{ SAM='svc-scvmm-agent';   Desc='SCVMM agent — local admin on Hyper-V hosts';        KVSecret='svc-scvmm-agent-password' },
    @{ SAM='svc-scvmm-runas';   Desc='SCVMM Run As account for cluster management';       KVSecret='svc-scvmm-runas-password' },
    @{ SAM='svc-sql-scvmm';     Desc='SQL Server service account for SCVMM database';     KVSecret='svc-sql-scvmm-password' },
    @{ SAM='svc-wac-gateway';   Desc='WAC vmode service account';                         KVSecret='svc-wac-gateway-password' }
)

foreach ($svc in $serviceAccounts) {
    $password = az keyvault secret show `
        --vault-name $KVName `
        --subscription $KVSubscription `
        --name $svc.KVSecret `
        --query value -o tsv | ConvertTo-SecureString -AsPlainText -Force

    try {
        New-ADUser -SamAccountName $svc.SAM `
            -Name $svc.SAM `
            -Description $svc.Desc `
            -AccountPassword $password `
            -Enabled $true `
            -PasswordNeverExpires $true `
            -CannotChangePassword $true `
            -Path $svcOU `
            -Server $DomainController
        Write-Host "  ✅ svc account: $($svc.SAM)"
    } catch {
        if ($_.Exception.Message -like '*already exists*') {
            Write-Host "  ⏭️  svc account: $($svc.SAM) already exists"
        } else { throw }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Security Groups
# ─────────────────────────────────────────────────────────────────────────────
$grpOU = "OU=Security Groups,$baseOU"

$groups = @(
    @{ Name='SG-TP-hvlab-clus01-HyperV-Administrators'; Desc='Full Hyper-V cluster admin' },
    @{ Name='SG-TP-hvlab-clus01-WAC-Administrators';    Desc='WAC vmode full admin' },
    @{ Name='SG-TP-hvlab-clus01-WAC-Users';             Desc='WAC vmode standard users (demo audience)' },
    @{ Name='SG-TP-hvlab-clus01-SCVMM-Administrators';  Desc='SCVMM administrator role' },
    @{ Name='SG-TP-hvlab-clus01-SCVMM-Users';           Desc='SCVMM self-service users (demo audience)' }
)

foreach ($grp in $groups) {
    try {
        New-ADGroup -Name $grp.Name -GroupScope Global -GroupCategory Security `
            -Description $grp.Desc -Path $grpOU -Server $DomainController
        Write-Host "  ✅ Group: $($grp.Name)"
    } catch {
        if ($_.Exception.Message -like '*already exists*') {
            Write-Host "  ⏭️  Group: $($grp.Name) already exists"
        } else { throw }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Kerberos Constrained Delegation for Live Migration
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`nConfiguring Kerberos Constrained Delegation for Live Migration..."
$clusterNodes = @('hvnode01','hvnode02','hvnode03','hvnode04')

foreach ($sourceNode in $clusterNodes) {
    $sourceAD = Get-ADComputer -Identity $sourceNode -Server $DomainController
    $allowedServices = @()
    foreach ($targetNode in $clusterNodes | Where-Object { $_ -ne $sourceNode }) {
        $allowedServices += "cifs/$targetNode"
        $allowedServices += "cifs/$targetNode.$DomainFqdn"
        $allowedServices += "Microsoft Virtual System Migration Service/$targetNode"
        $allowedServices += "Microsoft Virtual System Migration Service/$targetNode.$DomainFqdn"
    }
    Set-ADComputer -Identity $sourceAD `
        -TrustedForDelegation $false `
        -PrincipalsAllowedToDelegateToAccount $null `
        -Server $DomainController
    Set-ADObject -Identity $sourceAD `
        -Add @{'msDS-AllowedToDelegateTo' = $allowedServices } `
        -Server $DomainController
    Write-Host "  ✅ KCD configured for $sourceNode → $($clusterNodes | Where-Object{$_ -ne $sourceNode} | Join-String ', ')"
}

Write-Host "`n✅ Active Directory configuration complete."
