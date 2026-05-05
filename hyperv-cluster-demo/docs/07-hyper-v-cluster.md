# 07 — Hyper-V Failover Cluster

## Overview

| Property | Value |
|----------|-------|
| Cluster name | `hvlab-clus01` |
| Nodes | `hvnode01`, `hvnode02`, `hvnode03`, `hvnode04` |
| Storage | 3 × 500 GB iSCSI CSVs from `hviscsi01` |
| Quorum | Cloud Witness (Azure Blob — `sthvlabwitness01`) |
| Domain | `azrl.mgmt` |
| AD OU | `OU=ClusterNodes,OU=HVLab,OU=MMS2026,DC=azrl,DC=mgmt` |

---

## Prerequisites

Before running cluster setup:

- [ ] All 4 nodes domain-joined to `azrl.mgmt`
- [ ] CNO (`hvlab-clus01`) pre-staged in AD (see [`docs/05-active-directory.md`](05-active-directory.md))
- [ ] iSCSI disks visible on all 4 nodes with MPIO configured (see [`docs/06-iscsi-storage.md`](06-iscsi-storage.md))
- [ ] `Failover-Clustering` feature installed on all nodes
- [ ] KCD configured for live migration (see [`docs/05-active-directory.md`](05-active-directory.md))
- [ ] Cloud Witness storage account `sthvlabwitness01` created with access key in Key Vault

---

## Step 1 — Install Failover Clustering Role on All Nodes

```powershell
# Run on ALL four nodes (can be parallelized with Invoke-Command)
$nodes = @("hvnode01","hvnode02","hvnode03","hvnode04")

Invoke-Command -ComputerName $nodes -ScriptBlock {
    Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools
    Install-WindowsFeature -Name Hyper-V -IncludeManagementTools
    Install-WindowsFeature -Name Hyper-V-PowerShell
}

# Reboot all nodes
Invoke-Command -ComputerName $nodes -ScriptBlock { Restart-Computer -Force }

# Wait for nodes to come back
Start-Sleep -Seconds 120
foreach ($node in $nodes) {
    while (-not (Test-Connection $node -Count 1 -Quiet)) { Start-Sleep 10 }
    Write-Host "$node is back online"
}
```

---

## Step 2 — Cluster Validation

Run the cluster validation report before creating the cluster. This is **required** for a supported configuration and will catch any networking or storage issues.

```powershell
# Run validation from hvnode01 or a management machine
Test-Cluster `
  -Node "hvnode01","hvnode02","hvnode03","hvnode04" `
  -Include "Inventory","Network","Storage","System Configuration","Hyper-V Configuration" `
  -ReportName "C:\ClusterValidation\hvlab-validation"

# Review the report
Start-Process "C:\ClusterValidation\hvlab-validation.htm"
```

### Expected Validation Results

| Test Category | Expected Result |
|----------------|----------------|
| Network | Pass — multiple networks configured |
| Storage | Pass — iSCSI disks visible on all nodes |
| Hyper-V Configuration | Pass — nested virtualization enabled |
| System Configuration | Warnings are acceptable (eval OS, test environment) |

> **Do not proceed if Storage tests fail.** Storage failures mean the cluster will not function correctly. Resolve iSCSI connectivity issues first.

---

## Step 3 — Create the Cluster

```powershell
# Run from hvnode01 — the CNO must already be pre-staged in AD
New-Cluster `
  -Name "hvlab-clus01" `
  -Node "hvnode01","hvnode02","hvnode03","hvnode04" `
  -StaticAddress "172.16.10.50" `
  -AdministrativeAccessPoint "ActiveDirectoryAndDns" `
  -NoStorage  # Add storage separately below

# Verify cluster creation
Get-Cluster -Name "hvlab-clus01"
Get-ClusterNode -Cluster "hvlab-clus01"
```

> The cluster IP `172.16.10.50` is the Cluster Name Object (CNO) IP on the Mgmt network. This is used for Failover Cluster Manager connections and WAC/SCVMM cluster management.

---

## Step 4 — Add Storage to the Cluster

```powershell
# Add the iSCSI disks to the cluster
# First, identify the disk numbers (run on hvnode01)
Get-Disk | Where-Object BusType -eq "iSCSI" |
    Select-Object Number, Size, FriendlyName | Sort-Object Size

# Add all available storage to the cluster
Get-ClusterAvailableDisk -Cluster "hvlab-clus01" |
    Add-ClusterDisk

# Verify disks are added
Get-ClusterResource -Cluster "hvlab-clus01" |
    Where-Object ResourceType -eq "Physical Disk"
```

---

## Step 5 — Convert Disks to Cluster Shared Volumes

```powershell
# Get the cluster disk resources (exclude the small quorum disk)
$clusterDisks = Get-ClusterResource -Cluster "hvlab-clus01" |
    Where-Object ResourceType -eq "Physical Disk"

# Convert the 3 × 500 GB disks to CSVs (skip the 10 GB quorum disk)
foreach ($disk in $clusterDisks) {
    $physDisk = Get-ClusterParameter -InputObject $disk |
                Where-Object Name -eq "DiskSize"
    if ($physDisk.Value -gt 100GB) {
        Add-ClusterSharedVolume -InputObject $disk
        Write-Host "Added CSV: $($disk.Name)"
    }
}

# Rename CSVs to meaningful names
$csvs = Get-ClusterSharedVolume -Cluster "hvlab-clus01"
$csvs | Format-Table Name, State, SharedVolumeInfo

# Rename (adjust names based on what was created)
(Get-ClusterSharedVolume -Cluster "hvlab-clus01" -Name "Cluster Disk 2").Name = "CSV-Vol1"
(Get-ClusterSharedVolume -Cluster "hvlab-clus01" -Name "Cluster Disk 3").Name = "CSV-Vol2"
(Get-ClusterSharedVolume -Cluster "hvlab-clus01" -Name "Cluster Disk 4").Name = "CSV-Vol3"

# Verify CSV mount points (accessible as C:\ClusterStorage\Volume1, etc.)
Get-ClusterSharedVolume | Select-Object Name, State,
    @{N="Path";E={$_.SharedVolumeInfo.FriendlyVolumeName}}
```

---

## Step 6 — Configure Cloud Witness

```powershell
# Retrieve the witness storage account key from Key Vault
$witnessKey = az keyvault secret show `
  --vault-name "kv-hvlab-mms26-eus-01" `
  --name "hvlab-witness-storage-key" `
  --query value -o tsv

# Set Cloud Witness
Set-ClusterQuorum `
  -Cluster "hvlab-clus01" `
  -CloudWitness `
  -AccountName "sthvlabwitness01" `
  -AccessKey $witnessKey `
  -Endpoint "core.windows.net"

# Verify quorum configuration
Get-ClusterQuorum -Cluster "hvlab-clus01"
```

See [`docs/08-cloud-witness.md`](08-cloud-witness.md) for details on Cloud Witness behavior and graceful degradation.

---

## Step 7 — Configure Cluster Networks

After cluster creation, set the correct roles for each network:

```powershell
# View current cluster networks
Get-ClusterNetwork -Cluster "hvlab-clus01" | Select-Object Name, Address, Role

# Set network roles
# Role 0 = Do not allow cluster network communication
# Role 1 = Allow cluster network communication only
# Role 3 = Allow cluster network communication and client connectivity

# Mgmt network — allow both cluster and client
(Get-ClusterNetwork -Cluster "hvlab-clus01" |
    Where-Object Address -eq "172.16.10.0").Role = 3

# Migration network — cluster only
(Get-ClusterNetwork -Cluster "hvlab-clus01" |
    Where-Object Address -eq "172.16.20.0").Role = 1

# Heartbeat network — cluster only
(Get-ClusterNetwork -Cluster "hvlab-clus01" |
    Where-Object Address -eq "172.16.40.0").Role = 1

# Storage network — do NOT use for cluster communication
(Get-ClusterNetwork -Cluster "hvlab-clus01" |
    Where-Object Address -eq "172.16.30.0").Role = 0

# Rename networks for clarity
(Get-ClusterNetwork -Cluster "hvlab-clus01" | Where-Object Address -eq "172.16.10.0").Name = "Cluster-Mgmt"
(Get-ClusterNetwork -Cluster "hvlab-clus01" | Where-Object Address -eq "172.16.20.0").Name = "Cluster-Migration"
(Get-ClusterNetwork -Cluster "hvlab-clus01" | Where-Object Address -eq "172.16.30.0").Name = "Cluster-Storage"
(Get-ClusterNetwork -Cluster "hvlab-clus01" | Where-Object Address -eq "172.16.40.0").Name = "Cluster-Heartbeat"
```

---

## Step 8 — Configure Live Migration

```powershell
# On all cluster nodes — configure live migration settings
Invoke-Command -ComputerName @("hvnode01","hvnode02","hvnode03","hvnode04") -ScriptBlock {
    # Enable live migration
    Enable-VMMigration

    # Use Kerberos authentication (KCD configured in AD step)
    Set-VMHost -VirtualMachineMigrationAuthenticationType Kerberos

    # Limit concurrent live migrations to 4 (adequate for demo, avoids saturation)
    Set-VMHost -MaximumVirtualMachineMigrations 4

    # Set migration network to the Migration vSwitch
    Add-VMMigrationNetwork -Subnet "172.16.20.0/24" -Priority 1

    # Ensure the Mgmt network is lower priority for migration
    Add-VMMigrationNetwork -Subnet "172.16.10.0/24" -Priority 5
}
```

---

## Step 9 — VM Placement Rules for Demo

Configure preferred owners and failover policies for demo VMs to ensure predictable behavior during the presentation:

```powershell
# All demo cluster roles should have all nodes as possible owners
# Set preferred owners for demo scenarios

# Example: Create a demo VM resource with controlled placement
# This is run after demo VMs are added to the cluster

$demoVMs = Get-ClusterGroup -Cluster "hvlab-clus01" |
    Where-Object { $_.GroupType -eq "VirtualMachine" }

foreach ($vm in $demoVMs) {
    # Set all nodes as preferred owners (equal priority)
    Set-ClusterOwnerNode -InputObject $vm `
        -Owners "hvnode01","hvnode02","hvnode03","hvnode04"
    Write-Host "Set owners for: $($vm.Name)"
}

# Configure anti-affinity for better demo — spread VMs across nodes
# (SCVMM handles this better — use SCVMM placement for demo VMs)
```

---

## Verification

After completing all steps, run a final cluster health check:

```powershell
# Overall cluster health
Get-Cluster -Name "hvlab-clus01" | Select-Object Name, QuorumType, SharedVolumesRoot

# Node health
Get-ClusterNode -Cluster "hvlab-clus01" | Select-Object Name, State, ID

# Network health
Get-ClusterNetwork -Cluster "hvlab-clus01" | Select-Object Name, Role, State

# CSV health
Get-ClusterSharedVolume -Cluster "hvlab-clus01" | Select-Object Name, State,
    @{N="Owner";E={$_.OwnerNode.Name}},
    @{N="Path";E={$_.SharedVolumeInfo.FriendlyVolumeName}}

# Quorum health
Get-ClusterQuorum -Cluster "hvlab-clus01"

# Live migration test (migrate hvnode01's VMs to hvnode02)
# Get-ClusterGroup -Cluster "hvlab-clus01" | Where-Object OwnerNode -eq "hvnode01" |
#     Move-ClusterVirtualMachineRole -Node "hvnode02"
```

### Expected Healthy State

```
Cluster:  hvlab-clus01  QuorumType: CloudWitness
Nodes:    hvnode01-04   State: Up
Networks: Cluster-Mgmt (Role: 3), Cluster-Migration (Role: 1),
          Cluster-Heartbeat (Role: 1), Cluster-Storage (Role: 0)
CSVs:     CSV-Vol1, CSV-Vol2, CSV-Vol3  State: Online
Quorum:   CloudWitness  AccountName: sthvlabwitness01
```

---

## Troubleshooting

### Cluster Validation Fails on Storage

```powershell
# Confirm all nodes see the same disks
Invoke-Command -ComputerName @("hvnode01","hvnode02","hvnode03","hvnode04") -ScriptBlock {
    Get-Disk | Where-Object BusType -eq "iSCSI" |
        Select-Object Number, SerialNumber, Size | Sort-Object SerialNumber
}
# Serial numbers should match across all nodes for each disk
```

### Node Shows as Down

```powershell
# From a working node
Test-Connection hvnode02 -Count 3

# Check cluster node status and event log
Get-ClusterNode "hvnode02" | Select-Object Name, State, StatusInformation
Get-WinEvent -ComputerName hvnode02 -LogName "Microsoft-Windows-FailoverClustering/Operational" `
    -MaxEvents 20 | Select-Object TimeCreated, Message
```

### CSV Not Coming Online

```powershell
# Check which node owns the CSV and the underlying disk
Get-ClusterSharedVolume -Cluster "hvlab-clus01" | Select-Object Name, State, OwnerNode

# Check the physical disk resource
Get-ClusterResource -Cluster "hvlab-clus01" |
    Where-Object ResourceType -eq "Physical Disk" |
    Select-Object Name, State, OwnerGroup
```
