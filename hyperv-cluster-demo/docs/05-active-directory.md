# 05 — Active Directory

## Domain Overview

| Property | Value |
|----------|-------|
| Domain | `azrl.mgmt` |
| Forest functional level | Windows Server 2016 or higher |
| Existing DCs | `dc01.azrl.mgmt` (`10.250.1.36`), `dc02.azrl.mgmt` (`10.250.1.37`) |
| Replica DC (nested) | `hvdc01.azrl.mgmt` (`172.16.10.10`) |

> **Do not modify the existing DCs** at `10.250.1.36` and `10.250.1.37`. They serve production workloads. All demo-specific OU structure and accounts are self-contained under a dedicated OU.

---

## Why a Replica DC Inside the Nested Environment

The 4 cluster nodes (`hvnode01-04`) live on the isolated `172.16.10.0/24` management network with no direct routing to `10.250.1.36` or `10.250.1.37` (except via WinNAT, which does not preserve Kerberos tickets properly). Without a local DC:

- Kerberos authentication for cluster node domain joins would traverse WinNAT — unreliable
- Live migration Kerberos constrained delegation would fail intermittently
- Cluster validation tests that probe Kerberos would time out
- Any brief Azure network blip would cause cluster quorum issues as nodes fail to re-authenticate

`hvdc01` is a **read-write replica DC** (not RODC) placed in the same private network as the cluster nodes. It handles all Kerberos and LDAP for the nested environment locally.

---

## Host VM Domain Join

The host VM (`hv-host01`) joins `azrl.mgmt` directly using the existing DCs, since it has a NIC in `10.250.1.0/24` and can reach them:

```powershell
# On the host VM after deployment
$cred = Get-Credential  # svc-hvlab-deploy@azrl.mgmt
Add-Computer `
  -DomainName "azrl.mgmt" `
  -Credential $cred `
  -OUPath "OU=Servers,OU=HVLab,OU=MMS2026,DC=azrl,DC=mgmt" `
  -Restart
```

---

## Organizational Unit Structure

Create the following OUs under the domain root. All lab-specific objects live under `OU=MMS2026`:

```
DC=azrl,DC=mgmt
└── OU=MMS2026
    ├── OU=HVLab
    │   ├── OU=Servers          ← host VM and nested servers
    │   ├── OU=ClusterNodes     ← hvnode01-04 and CNO pre-stage
    │   └── OU=ServiceAccounts  ← all svc-* accounts
    └── OU=SecurityGroups       ← all lab security groups
```

### Create the OU Structure

```powershell
# Run on an existing DC or from a domain-joined admin workstation
Import-Module ActiveDirectory

$base = "DC=azrl,DC=mgmt"

New-ADOrganizationalUnit -Name "MMS2026" -Path $base
New-ADOrganizationalUnit -Name "HVLab" -Path "OU=MMS2026,$base"
New-ADOrganizationalUnit -Name "Servers" -Path "OU=HVLab,OU=MMS2026,$base"
New-ADOrganizationalUnit -Name "ClusterNodes" -Path "OU=HVLab,OU=MMS2026,$base"
New-ADOrganizationalUnit -Name "ServiceAccounts" -Path "OU=HVLab,OU=MMS2026,$base"
New-ADOrganizationalUnit -Name "SecurityGroups" -Path "OU=MMS2026,$base"
```

---

## Service Accounts

Six `svc-*` service accounts are required. All use the same base password stored in Key Vault secret `hvlab-svcaccount-password`.

| Account | UPN | Purpose |
|---------|-----|---------|
| `svc-hvlab-deploy` | `svc-hvlab-deploy@azrl.mgmt` | Deployment automation — domain joins, OU operations |
| `svc-hvlab-livemig` | `svc-hvlab-livemig@azrl.mgmt` | Kerberos constrained delegation for live migration |
| `svc-hvlab-cluster` | `svc-hvlab-cluster@azrl.mgmt` | Cluster service account (used by CNO) |
| `svc-hvlab-scvmm` | `svc-hvlab-scvmm@azrl.mgmt` | SCVMM service account |
| `svc-hvlab-sqlsvc` | `svc-hvlab-sqlsvc@azrl.mgmt` | SQL Server service account (SCVMM's SQL instance) |
| `svc-hvlab-wac` | `svc-hvlab-wac@azrl.mgmt` | WAC vMode service identity |

### Create All Service Accounts

```powershell
$svcOU = "OU=ServiceAccounts,OU=HVLab,OU=MMS2026,DC=azrl,DC=mgmt"
$password = ConvertTo-SecureString "<from-keyvault>" -AsPlainText -Force

$accounts = @(
    @{ Name = "svc-hvlab-deploy";  Description = "HVLab deployment automation" },
    @{ Name = "svc-hvlab-livemig"; Description = "HVLab live migration KCD" },
    @{ Name = "svc-hvlab-cluster"; Description = "HVLab cluster service account" },
    @{ Name = "svc-hvlab-scvmm";   Description = "HVLab SCVMM service account" },
    @{ Name = "svc-hvlab-sqlsvc";  Description = "HVLab SQL Server service account" },
    @{ Name = "svc-hvlab-wac";     Description = "HVLab WAC vMode service identity" }
)

foreach ($acct in $accounts) {
    New-ADUser `
        -Name $acct.Name `
        -SamAccountName $acct.Name `
        -UserPrincipalName "$($acct.Name)@azrl.mgmt" `
        -AccountPassword $password `
        -Description $acct.Description `
        -Path $svcOU `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -CannotChangePassword $true
    Write-Host "Created: $($acct.Name)"
}
```

### Delegate OU Permissions to svc-hvlab-deploy

The deployment account needs to join computers to specific OUs:

```powershell
# Grant "Create Computer Objects" and "Delete Computer Objects" on ClusterNodes OU
$clusterNodesOU = "OU=ClusterNodes,OU=HVLab,OU=MMS2026,DC=azrl,DC=mgmt"
$serversOU = "OU=Servers,OU=HVLab,OU=MMS2026,DC=azrl,DC=mgmt"

# Use dsacls or Active Directory delegation wizard
# Example with dsacls:
dsacls $clusterNodesOU /G "AZRL\svc-hvlab-deploy:CC;Computer"
dsacls $clusterNodesOU /G "AZRL\svc-hvlab-deploy:DC;Computer"
dsacls $serversOU /G "AZRL\svc-hvlab-deploy:CC;Computer"
dsacls $serversOU /G "AZRL\svc-hvlab-deploy:DC;Computer"
```

---

## Security Groups

Five security groups are needed to manage access and permissions:

| Group Name | Type | Scope | Purpose |
|------------|------|-------|---------|
| `sg-hvlab-admins` | Security | Global | Full admin access to all lab VMs |
| `sg-hvlab-clusteradmins` | Security | Global | Failover Cluster management |
| `sg-hvlab-livemig` | Security | Global | Live migration delegation rights |
| `sg-hvlab-scvmmadmins` | Security | Global | SCVMM admin console access |
| `sg-hvlab-wacadmins` | Security | Global | WAC vMode admin access |

### Create All Security Groups

```powershell
$groupOU = "OU=SecurityGroups,OU=MMS2026,DC=azrl,DC=mgmt"

$groups = @(
    @{ Name = "sg-hvlab-admins";       Description = "HVLab full admin" },
    @{ Name = "sg-hvlab-clusteradmins"; Description = "HVLab cluster admins" },
    @{ Name = "sg-hvlab-livemig";       Description = "HVLab live migration delegation" },
    @{ Name = "sg-hvlab-scvmmadmins";   Description = "HVLab SCVMM admins" },
    @{ Name = "sg-hvlab-wacadmins";     Description = "HVLab WAC vMode admins" }
)

foreach ($grp in $groups) {
    New-ADGroup `
        -Name $grp.Name `
        -SamAccountName $grp.Name `
        -GroupScope Global `
        -GroupCategory Security `
        -Description $grp.Description `
        -Path $groupOU
    Write-Host "Created group: $($grp.Name)"
}

# Add your admin account to the top-level group
Add-ADGroupMember -Identity "sg-hvlab-admins" -Members "svc-hvlab-deploy"
```

---

## Replica DC (hvdc01) Promotion

`hvdc01` is promoted as a replica DC for the `azrl.mgmt` domain. It replicates with the existing DCs at `10.250.1.36` and `10.250.1.37` over the External vSwitch (which has Azure NIC connectivity).

### Prerequisites on hvdc01 Before Promotion

```powershell
# Set static IP on Mgmt vSwitch NIC
New-NetIPAddress -IPAddress "172.16.10.10" -PrefixLength 24 `
  -DefaultGateway "172.16.10.1" `
  -InterfaceAlias "Ethernet"

# Point DNS at existing DCs for initial replication
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" `
  -ServerAddresses "10.250.1.36","10.250.1.37"

# Install AD DS role
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
```

### Promote as Replica DC

```powershell
$safeModePassword = ConvertTo-SecureString "<DSRM-password>" -AsPlainText -Force
$domainCred = Get-Credential  # svc-hvlab-deploy@azrl.mgmt

Install-ADDSDomainController `
  -DomainName "azrl.mgmt" `
  -Credential $domainCred `
  -InstallDns `
  -SiteName "HVLab" `
  -ReplicationSourceDC "dc01.azrl.mgmt" `
  -SafeModeAdministratorPassword $safeModePassword `
  -Force `
  -NoRebootOnCompletion:$false
```

### Post-Promotion DNS Configuration

After `hvdc01` is promoted, update DNS on all nested VMs to point to it as primary:

```powershell
# Run on each nested VM
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" `
  -ServerAddresses "172.16.10.10","10.250.1.36"
```

---

## Kerberos Constrained Delegation for Live Migration

Live migration between cluster nodes requires Kerberos constrained delegation (KCD) so that `hvnode01` can request Kerberos tickets on behalf of another node's computer account.

### Configure KCD on Each Cluster Node

```powershell
# Run on a DC — configure each node to allow delegation to the others
$nodes = @("hvnode01","hvnode02","hvnode03","hvnode04")

foreach ($source in $nodes) {
    $targets = $nodes | Where-Object { $_ -ne $source }
    foreach ($target in $targets) {
        # Allow source to delegate to target's Microsoft Virtual System Migration Service
        Set-ADComputer $source -Add @{
            'msDS-AllowedToDelegateTo' = @(
                "Microsoft Virtual System Migration Service/$target.azrl.mgmt",
                "Microsoft Virtual System Migration Service/$target",
                "cifs/$target.azrl.mgmt",
                "cifs/$target"
            )
        }
    }
    # Enable constrained delegation with protocol transition
    $computer = Get-ADComputer $source
    Set-ADObject $computer -Replace @{
        userAccountControl = $computer.userAccountControl -bor 0x1000000
    }
    Write-Host "KCD configured for $source"
}
```

### Verify KCD Configuration

```powershell
foreach ($node in @("hvnode01","hvnode02","hvnode03","hvnode04")) {
    $acl = Get-ADComputer $node -Properties "msDS-AllowedToDelegateTo" |
           Select-Object -ExpandProperty "msDS-AllowedToDelegateTo"
    Write-Host "=== $node ===" -ForegroundColor Cyan
    $acl | ForEach-Object { Write-Host "  $_" }
}
```

---

## AD Site Configuration

Create an AD site for the nested environment to optimize replication:

```powershell
# Create AD site for nested lab
New-ADReplicationSite -Name "HVLab" -Description "Nested HV lab environment"

# Create subnet entry
New-ADReplicationSubnet -Name "172.16.10.0/24" -Site "HVLab"
New-ADReplicationSubnet -Name "172.16.20.0/24" -Site "HVLab"
New-ADReplicationSubnet -Name "172.16.30.0/24" -Site "HVLab"

# Create site link (HVLab ↔ Default-First-Site-Name)
New-ADReplicationSiteLink `
  -Name "DEFAULTIPSITE-HVLab" `
  -SitesIncluded "Default-First-Site-Name","HVLab" `
  -Cost 100 `
  -ReplicationFrequencyInMinutes 15

# Move hvdc01 to HVLab site
$hvdc01 = Get-ADDomainController -Identity "hvdc01"
Move-ADDirectoryServer -Identity $hvdc01 -Site "HVLab"
```

---

## Pre-Staging the Cluster Name Object (CNO)

Before creating the Failover Cluster, pre-stage the cluster name object in AD to ensure it lands in the correct OU and has the right permissions:

```powershell
# Pre-stage the CNO in the ClusterNodes OU
$clusterNodesOU = "OU=ClusterNodes,OU=HVLab,OU=MMS2026,DC=azrl,DC=mgmt"

# Create the disabled computer account for the cluster
New-ADComputer `
  -Name "hvlab-clus01" `
  -SamAccountName "hvlab-clus01$" `
  -Path $clusterNodesOU `
  -Enabled $false `
  -Description "Hyper-V Failover Cluster CNO"

# Grant each cluster node's computer account Full Control over the CNO
foreach ($node in @("hvnode01","hvnode02","hvnode03","hvnode04")) {
    $nodeAccount = Get-ADComputer -Identity $node
    $cnoObject = Get-ADComputer -Identity "hvlab-clus01"

    # Set ACE — cluster nodes need Full Control over CNO
    $acl = Get-Acl "AD:$($cnoObject.DistinguishedName)"
    $sid = [System.Security.Principal.SecurityIdentifier]$nodeAccount.SID
    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sid,
        [System.DirectoryServices.ActiveDirectoryRights]::GenericAll,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $acl.AddAccessRule($ace)
    Set-Acl -AclObject $acl "AD:$($cnoObject.DistinguishedName)"
    Write-Host "Granted $node Full Control over hvlab-clus01 CNO"
}
```

See [`docs/07-hyper-v-cluster.md`](07-hyper-v-cluster.md) for the cluster creation steps that follow this pre-staging.
