# 06 — iSCSI Storage

## Overview

Shared storage for the Failover Cluster is provided by `hviscsi01` using the **Windows Server iSCSI Target Server** role — a free, built-in Windows Server feature that requires no additional licensing. The cluster nodes connect to the iSCSI target over two independent network paths (MPIO) on the dedicated Storage vSwitch.

---

## Why iSCSI Over SMB for This Demo

Failover Clustering supports multiple shared storage types, but iSCSI is chosen here for the following reasons:

| Consideration | iSCSI | SMB 3 (Scale-Out File Server) |
|---------------|-------|-------------------------------|
| Requires additional cluster | No — single server | Yes — requires a SOFS cluster |
| Windows built-in | Yes — no extra license | Yes — but requires extra VMs |
| MPIO support | Yes — dual paths | N/A (SMB multichannel) |
| Simulates real-world SAN | Yes | No |
| Demo complexity | Lower | Higher |

The primary requirement is **shared storage that Failover Clustering treats as a shared SCSI bus**. iSCSI satisfies this and allows demonstrating MPIO path failover — a realistic enterprise scenario.

---

## hviscsi01 VM Configuration

| Property | Value |
|----------|-------|
| vCPU | 4 |
| RAM | 16 GB |
| OS | Windows Server 2022 |
| Mgmt IP | `172.16.10.11` (vSwitch-Mgmt) |
| Storage IP 1 | `172.16.30.10` (vSwitch-Storage, path A) |
| Storage IP 2 | `172.16.30.11` (vSwitch-Storage, path B) |
| VHDX (OS) | 80 GB |
| VHDX (iSCSI data disk) | 2 TB (thin provisioned) |

The iSCSI data VHDX is kept separate from the OS VHDX. On demo day, move only the data VHDX to NVMe for performance.

---

## iSCSI Target Server Role Installation

```powershell
# On hviscsi01
Install-WindowsFeature -Name FS-iSCSITarget-Server -IncludeManagementTools

# Verify installation
Get-WindowsFeature -Name FS-iSCSITarget-Server
```

---

## LUN Layout

| LUN | Size | VHDX Name | Purpose |
|-----|------|-----------|---------|
| 0 | 10 GB | `quorum.vhdx` | Cluster quorum disk (deprecated in favor of Cloud Witness, but useful for testing) |
| 1 | 500 GB | `csv-vol1.vhdx` | Cluster Shared Volume 1 — workload VMs |
| 2 | 500 GB | `csv-vol2.vhdx` | Cluster Shared Volume 2 — workload VMs |
| 3 | 500 GB | `csv-vol3.vhdx` | Cluster Shared Volume 3 — workload VMs |

> The quorum disk is created for completeness but Cloud Witness is used as the actual quorum resource. See [`docs/08-cloud-witness.md`](08-cloud-witness.md).

### Create the iSCSI Virtual Disks and Target

```powershell
# On hviscsi01 — create the storage directory
New-Item -ItemType Directory -Path "E:\iSCSIVirtualDisks" -Force

# Create virtual disks (thin provisioned)
New-IscsiVirtualDisk `
  -Path "E:\iSCSIVirtualDisks\quorum.vhdx" `
  -Size 10GB

New-IscsiVirtualDisk `
  -Path "E:\iSCSIVirtualDisks\csv-vol1.vhdx" `
  -Size 500GB

New-IscsiVirtualDisk `
  -Path "E:\iSCSIVirtualDisks\csv-vol2.vhdx" `
  -Size 500GB

New-IscsiVirtualDisk `
  -Path "E:\iSCSIVirtualDisks\csv-vol3.vhdx" `
  -Size 500GB

# Create the iSCSI target
New-IscsiServerTarget `
  -TargetName "hvlab-clus01-target" `
  -InitiatorIds @(
      "IQN:iqn.1991-05.com.microsoft:hvnode01.azrl.mgmt",
      "IQN:iqn.1991-05.com.microsoft:hvnode02.azrl.mgmt",
      "IQN:iqn.1991-05.com.microsoft:hvnode03.azrl.mgmt",
      "IQN:iqn.1991-05.com.microsoft:hvnode04.azrl.mgmt"
  )

# Map virtual disks to the target
Add-IscsiVirtualDiskTargetMapping -TargetName "hvlab-clus01-target" `
  -Path "E:\iSCSIVirtualDisks\quorum.vhdx"

Add-IscsiVirtualDiskTargetMapping -TargetName "hvlab-clus01-target" `
  -Path "E:\iSCSIVirtualDisks\csv-vol1.vhdx"

Add-IscsiVirtualDiskTargetMapping -TargetName "hvlab-clus01-target" `
  -Path "E:\iSCSIVirtualDisks\csv-vol2.vhdx"

Add-IscsiVirtualDiskTargetMapping -TargetName "hvlab-clus01-target" `
  -Path "E:\iSCSIVirtualDisks\csv-vol3.vhdx"

# Verify
Get-IscsiServerTarget | Select-Object TargetName, IsConnected, InitiatorIds
Get-IscsiVirtualDisk | Select-Object Path, SizeBytes, IsAssigned
```

---

## iSCSI Initiator Configuration on Cluster Nodes

Run the following on each of `hvnode01` through `hvnode04`:

### Enable and Start iSCSI Initiator Service

```powershell
# On each cluster node
Start-Service MSiSCSI
Set-Service MSiSCSI -StartupType Automatic
```

### Set the Initiator IQN

The IQN must match exactly what was specified in the target's InitiatorIds above:

```powershell
# Check and set IQN (the default IQN is typically already correct)
$initiator = Get-InitiatorPort
Write-Host "Current IQN: $($initiator.NodeAddress)"

# If needed, set the IQN explicitly (rare — Windows sets this from hostname)
# The IQN should be: iqn.1991-05.com.microsoft:<hostname>.azrl.mgmt
```

### Connect to iSCSI Target (Both Paths)

```powershell
# Connect via path A (172.16.30.10)
New-IscsiTargetPortal `
  -TargetPortalAddress "172.16.30.10" `
  -InitiatorPortalAddress "172.16.30.21"  # Adjust last octet per node: .21, .22, .23, .24

Connect-IscsiTarget `
  -NodeAddress "iqn.1991-05.com.microsoft:hviscsi01-hvlab-clus01-target" `
  -TargetPortalAddress "172.16.30.10" `
  -InitiatorPortalAddress "172.16.30.21" `
  -IsPersistent $true

# Connect via path B (172.16.30.11) — second MPIO path
New-IscsiTargetPortal `
  -TargetPortalAddress "172.16.30.11" `
  -InitiatorPortalAddress "172.16.30.25"  # Adjust last octet per node: .25, .26, .27, .28

Connect-IscsiTarget `
  -NodeAddress "iqn.1991-05.com.microsoft:hviscsi01-hvlab-clus01-target" `
  -TargetPortalAddress "172.16.30.11" `
  -InitiatorPortalAddress "172.16.30.25" `
  -IsPersistent $true
```

### Node Storage IP Assignments

| Node | Path A IP | Path B IP |
|------|-----------|-----------|
| `hvnode01` | `172.16.30.21` | `172.16.30.25` |
| `hvnode02` | `172.16.30.22` | `172.16.30.26` |
| `hvnode03` | `172.16.30.23` | `172.16.30.27` |
| `hvnode04` | `172.16.30.24` | `172.16.30.28` |

---

## MPIO Configuration on Cluster Nodes

MPIO (Multipath I/O) must be installed and configured on every cluster node **before** running cluster validation:

```powershell
# On each cluster node — install MPIO feature
Install-WindowsFeature -Name Multipath-IO -IncludeManagementTools
Restart-Computer -Force  # MPIO requires reboot

# After reboot — enable MPIO for iSCSI devices
Enable-MSDSMAutomaticClaim -BusType iSCSI

# Set the load balancing policy to Round Robin
Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy RR

# Verify MPIO is claimed
Get-MSDSMAutomaticClaimSettings
Get-PhysicalDisk | Where-Object BusType -eq iSCSI | Select-Object FriendlyName, BusType
```

### Verify MPIO Paths

After connecting both iSCSI paths, verify that MPIO sees two paths per disk:

```powershell
# On each cluster node
Get-MSDSMSupportedHW
Get-Disk | Where-Object {$_.BusType -eq "iSCSI"} | ForEach-Object {
    $disk = $_
    Write-Host "Disk $($disk.Number): $($disk.FriendlyName)" -ForegroundColor Cyan
    Get-StorageReliabilityCounter -Disk $disk | Select-Object DeviceId
}

# Check MPIO path count (expect 2 per disk)
mpclaim -s -d
```

---

## Disk Preparation on First Cluster Node Only

Initialize and format the disks on `hvnode01` only. The other nodes will see the disks as cluster resources after cluster formation.

```powershell
# On hvnode01 ONLY
# Get the iSCSI disks
$iscsiDisks = Get-Disk | Where-Object {
    $_.BusType -eq "iSCSI" -and $_.PartitionStyle -eq "RAW"
} | Sort-Object Size

# Initialize each disk (GPT for disks > 2 TB; MBR is fine for these)
foreach ($disk in $iscsiDisks) {
    Initialize-Disk -Number $disk.Number -PartitionStyle GPT -PassThru |
    New-Partition -AssignDriveLetter -UseMaximumSize |
    Format-Volume -FileSystem NTFS -AllocationUnitSize 65536 `
        -NewFileSystemLabel "iSCSI-$($disk.Number)" -Confirm:$false
    Write-Host "Initialized disk $($disk.Number) ($([math]::Round($disk.Size/1GB)) GB)"
}
```

> After the Failover Cluster is created, these disks will be converted to Cluster Shared Volumes. Do not format them with any cluster-aware filesystem at this stage.

---

## Firewall Rules on hviscsi01

```powershell
# On hviscsi01 — ensure iSCSI Target firewall rules are enabled
Enable-NetFirewallRule -DisplayGroup "iSCSI Target (TCP-In)"
Enable-NetFirewallRule -DisplayGroup "iSCSI Target"

# Confirm
Get-NetFirewallRule | Where-Object DisplayGroup -like "*iSCSI*" |
    Select-Object DisplayName, Enabled, Direction
```

---

## Verification Checklist

After completing iSCSI setup, verify:

```powershell
# On hviscsi01 — confirm all 4 nodes are connected
Get-IscsiServerSession | Select-Object InitiatorNodeName, TargetName, IsConnected

# On each cluster node — confirm all 4 disks visible
Get-Disk | Where-Object BusType -eq "iSCSI" |
    Select-Object Number, FriendlyName, Size, HealthStatus

# Confirm MPIO — should show 2 active paths per disk
Get-MSDSMLoadBalancePolicy -Disk (Get-Disk | Where-Object BusType -eq "iSCSI")
```

Expected output: 4 iSCSI disks visible on each node, each with 2 MPIO paths, all showing `HealthStatus: Healthy`.
