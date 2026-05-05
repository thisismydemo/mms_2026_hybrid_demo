# 10 — SCVMM Setup

## Overview

`hvscvmm01` runs **System Center Virtual Machine Manager (SCVMM) 2025** with **SQL Server Developer Edition** as its database backend. SQL Server Developer is free for development and test use — it is functionally identical to SQL Server Enterprise but licensed only for non-production environments.

| Property | Value |
|----------|-------|
| VM | `hvscvmm01` |
| vCPU | 8 |
| RAM | 32 GB |
| OS | Windows Server 2022 |
| Mgmt IP | `172.16.10.40` (vSwitch-Mgmt) |
| External IP | `10.250.1.47` (vSwitch-External — reachable from on-prem) |
| SCVMM Console | Port 8100 |
| SQL instance | `HVSCVMM01\SCVMM` (named instance) |
| Domain | `azrl.mgmt` |

---

## Service Accounts Used by SCVMM

SCVMM requires two service accounts from the set created in [`docs/05-active-directory.md`](05-active-directory.md):

| Account | Service | Notes |
|---------|---------|-------|
| `svc-hvlab-scvmm` | VMM Service (vmmservice) | Must be a local admin on all Hyper-V hosts |
| `svc-hvlab-sqlsvc` | SQL Server (MSSQLSERVER, SQLSERVERAGENT) | Needs logon as a service right |

### Grant Required Rights

```powershell
# On hvscvmm01 — grant logon as a service to SQL account
# This is typically done via Group Policy or Local Security Policy
secedit /export /cfg "C:\Temp\secpol.cfg"
# Edit the file to add svc-hvlab-sqlsvc to SeServiceLogonRight
# Or use PowerShell with Carbon module, or ntrights.exe
```

---

## Installation Sequence

**CRITICAL**: SQL Server must be installed and configured **before** running the SCVMM installer. SCVMM will fail if it cannot connect to SQL during setup.

### Step 1 — Install SQL Server Developer Edition

```powershell
# Download SQL Server 2022 Developer (free)
$sqlInstallerUrl = "https://go.microsoft.com/fwlink/p/?linkid=2215158&clcid=0x409&culture=en-us&country=us"
Invoke-WebRequest -Uri $sqlInstallerUrl -OutFile "C:\Installers\SQLServer2022-DEV-x64-ENU.exe" -UseBasicParsing

# Run SQL setup
Start-Process -FilePath "C:\Installers\SQLServer2022-DEV-x64-ENU.exe" `
  -ArgumentList "/ACTION=Install /QUIET /IACCEPTSQLSERVERLICENSETERMS /FEATURES=SQLEngine,FullText /INSTANCENAME=SCVMM /SQLSVCACCOUNT=`"AZRL\svc-hvlab-sqlsvc`" /SQLSVCPASSWORD=`"<password>`" /SQLSYSADMINACCOUNTS=`"AZRL\sg-hvlab-admins`" /AGTSVCACCOUNT=`"AZRL\svc-hvlab-sqlsvc`" /AGTSVCPASSWORD=`"<password>`" /SQLCOLLATION=SQL_Latin1_General_CP1_CI_AS /TCPENABLED=1 /NPENABLED=0 /BROWSERSVCSTARTUPTYPE=Automatic /AGTSVCSTARTUPTYPE=Automatic /SECURITYMODE=SQL /SAPWD=`"<sa-password-from-kv>`"" `
  -Wait

# Verify SQL Server instance
Get-Service -Name "MSSQL`$SCVMM" | Select-Object Name, Status, StartType
```

### Step 2 — Configure SQL Server for SCVMM

```powershell
# Enable Named Pipes and TCP/IP for SCVMM connectivity
# SQL Server Configuration Manager — use PowerShell SMO
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | Out-Null

$smo = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer "hvscvmm01"
$uri = "ManagedComputer[@Name='HVSCVMM01']/ServerInstance[@Name='SCVMM']/ServerProtocol[@Name='Tcp']"
$Tcp = $smo.GetSmoObject($uri)
$Tcp.IsEnabled = $true
$Tcp.Alter()

# Restart SQL Server
Restart-Service -Name "MSSQL`$SCVMM" -Force
Start-Sleep 15

# Verify SQL connectivity
Invoke-Sqlcmd -ServerInstance "HVSCVMM01\SCVMM" -Query "SELECT @@VERSION" -TrustServerCertificate
```

### Step 3 — Install SCVMM 2025

Obtain the SCVMM 2025 installer from VLSC or your MSDN subscription. Mount the ISO:

```powershell
# Mount the SCVMM 2025 ISO
Mount-DiskImage -ImagePath "C:\Installers\SCVMM2025.iso"
$drive = (Get-DiskImage -ImagePath "C:\Installers\SCVMM2025.iso" | Get-Volume).DriveLetter

# Run silent installation
Start-Process -FilePath "${drive}:\Setup\setup.exe" -ArgumentList `
    "/server /i /client /f C:\Installers\SCVMMSetup.ini /IACCEPTSCULICENSETERMS" -Wait

# Or interactive installation (recommended for first-time setup)
Start-Process -FilePath "${drive}:\Setup\setup.exe"
```

### SCVMM Setup INI File

Create `C:\Installers\SCVMMSetup.ini` for silent installation:

```ini
[OPTIONS]
CompanyName=AzureLocal MMS26 Lab
UserName=HVLab Admin
ProductKey=<from-keyvault-hvlab-scvmm-product-key>
CreateNewSqlDatabase=1
SqlInstanceServer=HVSCVMM01\SCVMM
SqlDatabaseName=VirtualManagerDB
IndigoTcpPort=8100
IndigoHTTPSPort=8101
IndigoNETTCPPort=8102
IndigoHTTPPort=8103
WSManTcpPort=5985
BitsTcpPort=443
RemoteSetup=0
VmmServiceLocalAccount=0
VMMServiceDomain=AZRL
VMMServiceUserName=svc-hvlab-scvmm
VMMServiceUserPassword=<password>
TopContainerName=MSSCVMMLibrary
```

### Step 4 — Install SCVMM Admin Console

Install the SCVMM console on the same server (and optionally on `hv-host01` for remote management):

```powershell
# Install console only (on management machines)
Start-Process -FilePath "${drive}:\Setup\setup.exe" -ArgumentList `
    "/client /i /f C:\Installers\SCVMMConsoleSetup.ini /IACCEPTSCULICENSETERMS" -Wait
```

---

## Post-Installation Configuration

### Add Hyper-V Hosts to SCVMM

```powershell
# Open SCVMM PowerShell
Import-Module VirtualMachineManager

# Connect to SCVMM server
$vmmServer = Get-SCVMMServer -ComputerName "hvscvmm01.azrl.mgmt"

# Create a Run As Account for host credentials
$hostCred = Get-Credential -Message "Enter svc-hvlab-scvmm credentials"
$runAsAccount = New-SCRunAsAccount `
    -Name "HVLab-HostRunAs" `
    -Credential $hostCred `
    -VMMServer $vmmServer

# Add each Hyper-V host
$nodes = @("hvnode01.azrl.mgmt","hvnode02.azrl.mgmt","hvnode03.azrl.mgmt","hvnode04.azrl.mgmt")

foreach ($node in $nodes) {
    Add-SCVMHost `
        -ComputerName $node `
        -Credential $runAsAccount `
        -RunAsynchronously `
        -VMMServer $vmmServer
    Write-Host "Adding host: $node"
}

# Wait and verify
Start-Sleep 60
Get-SCVMHost -VMMServer $vmmServer | Select-Object Name, OverallState, CommunicationState
```

### Add the Cluster to SCVMM

```powershell
# Add the Failover Cluster
Add-SCVMHostCluster `
    -Name "hvlab-clus01.azrl.mgmt" `
    -Credential $runAsAccount `
    -VMMServer $vmmServer

# Verify
Get-SCVMHostCluster -VMMServer $vmmServer | Select-Object Name, ClusterStatus
```

---

## Configure Logical Networks

SCVMM logical networks must map to the vSwitches defined on the Hyper-V hosts:

```powershell
# Create logical networks matching the vSwitch layout
$vmmServer = Get-SCVMMServer -ComputerName "hvscvmm01.azrl.mgmt"

# Management network
$mgmtNetwork = New-SCLogicalNetwork `
    -Name "HVLab-Mgmt" `
    -Description "Management network 172.16.10.0/24" `
    -VMMServer $vmmServer

New-SCLogicalNetworkDefinition `
    -Name "HVLab-Mgmt-Def" `
    -LogicalNetwork $mgmtNetwork `
    -SubnetVLan (New-SCSubnetVLan -Subnet "172.16.10.0/24") `
    -VMMServer $vmmServer

# Workload network
$workloadNetwork = New-SCLogicalNetwork `
    -Name "HVLab-Workload" `
    -Description "Workload VM network 172.16.50.0/24" `
    -VMMServer $vmmServer

New-SCLogicalNetworkDefinition `
    -Name "HVLab-Workload-Def" `
    -LogicalNetwork $workloadNetwork `
    -SubnetVLan (New-SCSubnetVLan -Subnet "172.16.50.0/24") `
    -VMMServer $vmmServer

# Create VM Networks from logical networks
New-SCVMNetwork `
    -Name "VMNet-Workload" `
    -LogicalNetwork $workloadNetwork `
    -IsolationType "NoIsolation" `
    -VMMServer $vmmServer

# Verify
Get-SCLogicalNetwork -VMMServer $vmmServer | Select-Object Name, Description
Get-SCVMNetwork -VMMServer $vmmServer | Select-Object Name, LogicalNetwork
```

---

## Library Server Setup

```powershell
# The default library share is created on hvscvmm01 during installation
# Verify and add VM templates / ISOs

$library = Get-SCLibraryShare -VMMServer $vmmServer
Write-Host "Library share: $($library.Path)"

# Add ISO files to the library
# Copy ISOs to the library share path first
$libraryPath = $library.Path.Replace("\\hvscvmm01\", "C:\")
Copy-Item "C:\Installers\WS2022_SERVER_EVAL_x64FRE_en-us.iso" $libraryPath
Copy-Item "C:\Installers\WS2025_SERVER_EVAL_x64FRE_en-us.iso" $libraryPath

# Refresh library
Read-SCLibraryShare -LibraryShare $library
```

---

## Run As Accounts

```powershell
# Create all Run As accounts for the demo
$accounts = @(
    @{ Name = "HVLab-DomainAdmin"; Username = "AZRL\svc-hvlab-deploy" },
    @{ Name = "HVLab-SCVMMService"; Username = "AZRL\svc-hvlab-scvmm" },
    @{ Name = "HVLab-HostMgmt";    Username = "AZRL\sg-hvlab-admins" }
)

foreach ($acct in $accounts) {
    $cred = New-Object System.Management.Automation.PSCredential(
        $acct.Username,
        (ConvertTo-SecureString "<password>" -AsPlainText -Force)
    )
    New-SCRunAsAccount `
        -Name $acct.Name `
        -Credential $cred `
        -VMMServer $vmmServer
    Write-Host "Created Run As account: $($acct.Name)"
}
```

---

## Key Demo Scenarios

### Scenario 1 — Deploy a VM from Template

1. In SCVMM Console → **VMs and Services** → **Create Virtual Machine**
2. Select a VM template (create one from WS2022 ISO if not already done)
3. Select destination cluster `hvlab-clus01` and CSV (`CSV-Vol1`)
4. SCVMM automatically places the VM on the least-loaded node
5. Show the automatic cloud (VM networks and logical networks applied)

### Scenario 2 — Cluster Management

1. Navigate to **Fabric** → **Servers** → `hvlab-clus01`
2. Show all 4 nodes with health status and resource utilization
3. Right-click a node → **Put to Maintenance** → show VMs live-migrating automatically
4. Right-click the node → **Resume** → VMs can be migrated back

### Scenario 3 — Connect to Azure

SCVMM 2025 supports Azure integration for hybrid scenarios:
1. In SCVMM Console → **Settings** → **Azure Management** → **Add Azure Subscription**
2. Enter subscription ID `00cd4357-ed45-4efb-bee0-10c467ff994b`
3. Show Azure VMs and on-premises VMs in the same management pane

### Scenario 4 — Storage Management

1. Navigate to **Fabric** → **Storage** → show CSVs
2. Create a VM disk on `CSV-Vol2` and show the thin-provisioning details
3. Show MPIO path status for iSCSI disks

---

## Troubleshooting

### SCVMM Service Won't Start

```powershell
# Check service status and dependencies
Get-Service -Name "vmmservice" | Select-Object Name, Status, StartType

# Check SQL Server connectivity
Test-NetConnection -ComputerName "HVSCVMM01" -Port 1433

# Check SCVMM event log
Get-WinEvent -LogName "Operations Manager" -MaxEvents 20 -ErrorAction SilentlyContinue
Get-WinEvent -ProviderName "Microsoft-VirtualMachineManager-*" -MaxEvents 20 -ErrorAction SilentlyContinue
```

### Host in "Needs Attention" State

```powershell
# Refresh host agent
$host = Get-SCVMHost -ComputerName "hvnode01.azrl.mgmt"
Read-SCVMHost -VMHost $host

# If agent needs reinstall
Install-SCVMHostAgent -VMHost $host

# Check WinRM from SCVMM server
Test-WSMan -ComputerName "hvnode01.azrl.mgmt" -Credential $hostCred
```
