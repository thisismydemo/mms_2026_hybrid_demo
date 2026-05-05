# 08 — Cloud Witness

## Overview

The `hvlab-clus01` Failover Cluster uses **Azure Blob Storage Cloud Witness** as its quorum resource instead of a traditional disk witness or file share witness.

| Property | Value |
|----------|-------|
| Quorum type | Cloud Witness |
| Storage account | `sthvlabwitness01` |
| Container | `msft-cloud-witness` (auto-created by Windows) |
| Blob name | `hvlab-clus01` |
| Region | East US |
| SKU | Standard_LRS |

---

## Why Cloud Witness Over Disk Witness

| Consideration | Cloud Witness | Disk Witness |
|---------------|---------------|-------------|
| Requires a dedicated shared disk | No | Yes (wastes a LUN) |
| Single point of failure risk | Low (Azure HA) | Higher (single disk) |
| Needs quorum disk online for failover | No | Yes |
| Works with even number of nodes | Yes | Yes |
| Survives site-level failures | Yes (Azure is external) | No |
| Configuration complexity | Low | Medium |
| Cost | Negligible (<$1/month) | 1 wasted LUN |

For a demo environment where the cluster nodes are all on a single host, a Cloud Witness is strongly preferred. If the entire host VM becomes unresponsive, the Cloud Witness is still accessible from any surviving connection — it's genuinely external to the nested environment.

---

## Storage Account Configuration

The storage account `sthvlabwitness01` is created with the following settings:

```powershell
az storage account create `
  --name "sthvlabwitness01" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --location "eastus" `
  --sku Standard_LRS `
  --kind StorageV2 `
  --access-tier Hot `
  --min-tls-version TLS1_2 `
  --allow-blob-public-access false `
  --https-only true
```

### Retrieve the Access Key

```powershell
$key = az storage account keys list `
  --account-name "sthvlabwitness01" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --query "[0].value" -o tsv

# Store in Key Vault
az keyvault secret set `
  --vault-name "kv-hvlab-mms26-eus-01" `
  --name "hvlab-witness-storage-key" `
  --value $key

Write-Host "Key stored in Key Vault: kv-hvlab-mms26-eus-01"
```

---

## Configure Cloud Witness on the Cluster

Run from a cluster node or management machine after the cluster is created:

```powershell
# Retrieve key from Key Vault
$witnessKey = az keyvault secret show `
  --vault-name "kv-hvlab-mms26-eus-01" `
  --name "hvlab-witness-storage-key" `
  --query value -o tsv

# Configure Cloud Witness
Set-ClusterQuorum `
  -Cluster "hvlab-clus01" `
  -CloudWitness `
  -AccountName "sthvlabwitness01" `
  -AccessKey $witnessKey `
  -Endpoint "core.windows.net"

# Verify
Get-ClusterQuorum -Cluster "hvlab-clus01" | Format-List *
```

### Expected Output

```
Cluster              : hvlab-clus01
QuorumResource       : Cloud Witness
QuorumType           : CloudWitness
```

---

## How Cloud Witness Works

The Cloud Witness blob file serves as a tiebreaker vote in split-brain scenarios:

```
Normal operation (4 nodes + Cloud Witness = 5 votes):
  hvnode01: 1 vote
  hvnode02: 1 vote
  hvnode03: 1 vote
  hvnode04: 1 vote
  Cloud Witness: 1 vote
  Total: 5 votes — majority requires 3
```

If two nodes become isolated from the other two (network partition), the group that can still reach the Cloud Witness blob has a majority (2 node votes + 1 witness = 3) and continues running. The isolated side (2 votes, cannot reach witness) gracefully fences itself.

---

## What Happens If Azure Connectivity Drops During the Demo

### Scenario: Temporary Azure Network Blip (< 1 minute)

The cluster continues operating normally. The Cloud Witness vote is only consulted during quorum calculations, which occur at node failure/join events — not continuously. A brief network interruption does not trigger a recalculation.

### Scenario: Sustained Azure Connectivity Loss (> 5 minutes)

The cluster continues operating as long as all 4 nodes remain healthy:

```
4 nodes running, Cloud Witness unreachable:
  hvnode01-04: 4 votes
  Cloud Witness: 0 votes (unreachable — abstains)
  Effective quorum: 4 votes, majority requires 3
  Result: Cluster remains online
```

The cluster only loses quorum if it also loses a node simultaneously with losing the witness.

### Scenario: Azure Connectivity Loss + 1 Node Failure

```
3 nodes running, Cloud Witness unreachable:
  Remaining nodes: 3 votes
  Cloud Witness: 0 votes (unreachable)
  Effective quorum: 3 votes, majority requires 3 (of total 4 node votes)
  Result: Cluster ONLINE — 3/4 nodes is still a majority
```

The cluster survives losing one node even without the witness, because 3 out of 4 node votes is still a majority.

### Scenario: Azure Connectivity Loss + 2 Nodes Failure

```
2 nodes running, Cloud Witness unreachable:
  Remaining nodes: 2 votes
  Cloud Witness: 0 votes (unreachable)
  Effective quorum: 2 votes — NOT a majority (need 3 of 4)
  Result: Cluster OFFLINE — graceful self-fencing
```

This is the correct and expected behavior for a split-brain cluster. VMs are terminated cleanly on the remaining two nodes before they fence.

### Demo Day Mitigation

For demo day, the Azure connection is stable by design (the host VM itself is in Azure, so the connection to the Cloud Witness blob is an internal Azure network path, not over the internet). The witness storage account is in the **same Azure region** (East US) as the host VM, making the path extremely reliable.

---

## Monitoring Cloud Witness Connectivity

```powershell
# Test connectivity to the witness storage account from a cluster node
$storageUri = "https://sthvlabwitness01.blob.core.windows.net/"
$response = Invoke-WebRequest -Uri $storageUri -UseBasicParsing -TimeoutSec 10
Write-Host "Storage account reachable: $($response.StatusCode)"

# Check cluster quorum status
Get-ClusterQuorum -Cluster "hvlab-clus01"

# View quorum events
Get-WinEvent -LogName "Microsoft-Windows-FailoverClustering/Operational" `
  -MaxEvents 50 |
  Where-Object { $_.Message -like "*witness*" -or $_.Message -like "*quorum*" } |
  Select-Object TimeCreated, Message
```

---

## Key Rotation

If the storage account access key needs to be rotated:

```powershell
# Rotate to key 2
az storage account keys renew `
  --account-name "sthvlabwitness01" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --key primary

# Get the new key
$newKey = az storage account keys list `
  --account-name "sthvlabwitness01" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --query "[0].value" -o tsv

# Update Key Vault
az keyvault secret set `
  --vault-name "kv-hvlab-mms26-eus-01" `
  --name "hvlab-witness-storage-key" `
  --value $newKey

# Update cluster witness with new key (must be done while cluster is healthy)
Set-ClusterQuorum `
  -Cluster "hvlab-clus01" `
  -CloudWitness `
  -AccountName "sthvlabwitness01" `
  -AccessKey $newKey `
  -Endpoint "core.windows.net"
```
