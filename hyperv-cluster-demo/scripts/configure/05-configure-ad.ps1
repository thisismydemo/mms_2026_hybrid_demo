##############################################################################
# 05-configure-ad.ps1  — Create OUs, service accounts, and security groups
# Run from: self-hosted runner OR any domain-joined machine with AD RSAT
# Target DC: hvdc01 (forest root DC for azrl.mgmt on vSwitch-Mgmt)
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

function New-SecureStringValue {
    param([string]$Value)

    $secureString = New-Object System.Security.SecureString
    foreach ($character in $Value.ToCharArray()) {
        $secureString.AppendChar($character)
    }
    $secureString.MakeReadOnly()
    return $secureString
}

$domainDN = "DC=$($DomainFqdn.Replace('.',',DC='))"
$baseOU   = "OU=MGMT,$domainDN"

$ous = @(
    @{ Name = 'Servers';         Path = $baseOU },
    @{ Name = 'Clusters';        Path = "OU=Servers,$baseOU" },
    @{ Name = 'hvlab-clus01';    Path = "OU=Clusters,OU=Servers,$baseOU" },
    @{ Name = 'hvlab-servers';   Path = "OU=Servers,$baseOU" },
    @{ Name = 'ServiceAccounts'; Path = $baseOU },
    @{ Name = 'Security Groups'; Path = $baseOU }
)

foreach ($ou in $ous) {
    try {
        New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path `
            -Server $DomainController -ProtectedFromAccidentalDeletion $false
        Write-Host "  ✅ OU: $($ou.Name)"
    } catch {
        if ($_.Exception.Message -like '*already exists*') {
            Write-Host "  ⏭️  OU: $($ou.Name) already exists"
        } else {
            throw
        }
    }
}

$svcOU = "OU=ServiceAccounts,$baseOU"

$serviceAccounts = @(
    @{ SAM = 'svc-hvlab-deploy'; Desc = 'HV-Lab bootstrap and deployment account';       KVSecret = 'svc-hvlab-deploy-password' },
    @{ SAM = 'svc-scvmm-svc';    Desc = 'SCVMM management server service account';       KVSecret = 'svc-scvmm-svc-password' },
    @{ SAM = 'svc-scvmm-agent';  Desc = 'SCVMM agent — local admin on Hyper-V hosts';    KVSecret = 'svc-scvmm-agent-password' },
    @{ SAM = 'svc-scvmm-runas';  Desc = 'SCVMM Run As account for cluster management';   KVSecret = 'svc-scvmm-runas-password' },
    @{ SAM = 'svc-sql-scvmm';    Desc = 'SQL Server service account for SCVMM database'; KVSecret = 'svc-sql-scvmm-password' },
    @{ SAM = 'svc-wac-gateway';  Desc = 'WAC vmode service account';                     KVSecret = 'svc-wac-gateway-password' }
)

foreach ($svc in $serviceAccounts) {
    $plainSecret = az keyvault secret show `
        --vault-name $KVName `
        --subscription $KVSubscription `
        --name $svc.KVSecret `
        --query value -o tsv

    $password = New-SecureStringValue -Value $plainSecret

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
        } else {
            throw
        }
    }
}

$grpOU = "OU=Security Groups,$baseOU"

$groups = @(
    @{ Name = 'SG-TP-hvlab-clus01-HyperV-Administrators'; Desc = 'Full Hyper-V cluster admin' },
    @{ Name = 'SG-TP-hvlab-clus01-WAC-Administrators';    Desc = 'WAC vmode full admin' },
    @{ Name = 'SG-TP-hvlab-clus01-WAC-Users';             Desc = 'WAC vmode standard users (demo audience)' },
    @{ Name = 'SG-TP-hvlab-clus01-SCVMM-Administrators';  Desc = 'SCVMM administrator role' },
    @{ Name = 'SG-TP-hvlab-clus01-SCVMM-Users';           Desc = 'SCVMM self-service users (demo audience)' }
)

foreach ($grp in $groups) {
    try {
        New-ADGroup -Name $grp.Name -GroupScope Global -GroupCategory Security `
            -Description $grp.Desc -Path $grpOU -Server $DomainController
        Write-Host "  ✅ Group: $($grp.Name)"
    } catch {
        if ($_.Exception.Message -like '*already exists*') {
            Write-Host "  ⏭️  Group: $($grp.Name) already exists"
        } else {
            throw
        }
    }
}

Write-Host "`nConfiguring Kerberos Constrained Delegation for Live Migration..."
$clusterNodes = @('hvnode01', 'hvnode02', 'hvnode03', 'hvnode04')

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
    Write-Host "  ✅ KCD configured for $sourceNode → $($clusterNodes | Where-Object { $_ -ne $sourceNode } | Join-String ', ')"
}

Write-Host "`nConfiguring DNS Forwarder on $DomainController..."

Invoke-Command -ComputerName $DomainController -ScriptBlock {
    Get-DnsServerForwarder | Remove-DnsServerForwarder -Force -ErrorAction SilentlyContinue
    Add-DnsServerForwarder -IPAddress '168.63.129.16', '1.1.1.1' -PassThru
    Write-Host "  ✅ DNS forwarders set: 168.63.129.16 (Azure DNS), 1.1.1.1 (fallback)"
    Set-DnsServerForwarder -UseRootHint $false
    Write-Host "  ✅ Root hints disabled (forwarder-only mode)"
}

Write-Host "`n✅ Active Directory configuration complete."
