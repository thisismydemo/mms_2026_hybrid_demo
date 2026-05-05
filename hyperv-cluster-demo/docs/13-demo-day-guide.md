# 13 — Demo Day Guide

## Pre-Demo Checklist

Complete this checklist at least **30 minutes before** the session begins:

### Environment Health

- [ ] RDP to `hv-host01` (10.250.1.45) successfully
- [ ] All nested VMs are Running: `Get-VM | Select-Object Name, State`
- [ ] Cluster is healthy: `Get-ClusterNode -Cluster hvlab-clus01 | Select-Object Name, State` — all `Up`
- [ ] All CSVs Online: `Get-ClusterSharedVolume -Cluster hvlab-clus01 | Select-Object Name, State`
- [ ] Cloud Witness reachable: `Get-ClusterQuorum -Cluster hvlab-clus01`

### WAC vMode (Session 1)

- [ ] `https://10.250.1.46` loads without certificate error
- [ ] All 4 cluster nodes show as **Connected** in WAC vMode
- [ ] At least 2 demo VMs are running on different cluster nodes (verify node placement)
- [ ] PostgreSQL service running on `hvwac01`

### SCVMM (Session 2)

- [ ] SCVMM console connects to `hvscvmm01.azrl.mgmt:8100`
- [ ] `hvlab-clus01` shows **OK** in SCVMM Fabric view
- [ ] At least 1 VM template available in library
- [ ] SQL Server service running on `hvscvmm01`

### Connectivity

- [ ] From on-premises machine: `Test-Connection 10.250.1.46 -Count 2` succeeds
- [ ] From on-premises machine: `Test-Connection 10.250.1.47 -Count 2` succeeds
- [ ] Azure Local cluster node can reach `10.250.1.46`

---

## Restoring the DEMO-READY Checkpoint

If anything is broken or the environment needs to be reset to a clean state:

### Option 1 — GitHub Actions (Preferred)

1. Navigate to: **GitHub → Repository → Actions → hvlab-07-demo-reset**
2. Click **Run workflow** → select branch `main`
3. Click **Run workflow**
4. Wait approximately 20 minutes
5. Re-run the pre-demo checklist above

### Option 2 — Manual Reset from Host VM

```powershell
# On hv-host01 — restore all VMs to DEMO-READY checkpoint
$vms = Get-VM
foreach ($vm in $vms) {
    # Stop VM if running
    if ($vm.State -eq "Running") {
        Stop-VM -VM $vm -Force
    }
    # Restore checkpoint
    $checkpoint = Get-VMSnapshot -VM $vm -Name "DEMO-READY"
    if ($checkpoint) {
        Restore-VMSnapshot -VMSnapshot $checkpoint -Confirm:$false
        Start-VM -VM $vm
        Write-Host "Restored: $($vm.Name)"
    } else {
        Write-Host "⚠ No DEMO-READY checkpoint found for $($vm.Name)" -ForegroundColor Yellow
    }
}
```

### Expected Post-Reset State

After restoration:

| VM | State | Notes |
|----|-------|-------|
| `hvdc01` | Running | DC services started |
| `hviscsi01` | Running | iSCSI target serving 4 LUNs |
| `hvnode01-04` | Running | Cluster nodes Up, CSVs Online |
| `hvwac01` | Running | WAC vMode web UI accessible at 10.250.1.46 |
| `hvscvmm01` | Running | SCVMM console accessible at 10.250.1.47:8100 |

---

## Session 1 Walkthrough — WAC Virtualization Mode

**Duration**: ~25 minutes  
**URL**: `https://10.250.1.46`

### Talking Points Opening (2 min)

- WAC Virtualization Mode is **not** WAC Administration Mode — completely different product
- Purpose-built for Hyper-V fabric management: stateful agents, PostgreSQL backend
- WS2025 only during preview
- Today's demo: manage a 4-node Hyper-V cluster the same way an Azure Local operator would

### Demo Step 1 — Cluster Overview (3 min)

1. Open `https://10.250.1.46` from your demo machine
2. Log in as `AZRL\<admin-account>`
3. Navigate to **Cluster** → `hvlab-clus01`
4. Show the **Overview** tab: node health, CSV status, cluster events
5. **Talking point**: Real-time agent data, not polling — the health view updates without page refresh

### Demo Step 2 — Host Health Dashboard (4 min)

1. Navigate to **Hosts** → click `hvnode01`
2. Show **CPU** utilization graph (real-time)
3. Show **Memory** pressure and NUMA topology
4. Show **Network** adapter throughput across all vNICs
5. Show **Storage** — iSCSI paths and MPIO status
6. **Talking point**: This is the same depth of host telemetry that Azure Monitor provides for Azure VMs — now available for on-prem Hyper-V through the WAC vMode agent

### Demo Step 3 — Live Migration (8 min)

1. Navigate to **Virtual Machines** — show VMs distributed across nodes
2. Select a VM on `hvnode01`
3. Click **Move** → select `hvnode03` as destination
4. Click **Move** and watch the status bar

```
Expected behavior:
  - VM disappears from hvnode01 VM list
  - VM appears on hvnode03 within ~30 seconds
  - No guest OS restart — live migration is near-zero downtime
```

5. After migration completes: navigate back to **Hosts** → `hvnode01` to show reduced load
6. **Talking point**: Kerberos constrained delegation is what makes this work — no password prompts, the cluster nodes trust each other via AD delegation

### Demo Step 4 — Create a VM (8 min)

1. Navigate to **Virtual Machines** → **New VM**
2. Configure:
   - Name: `demo-workload-01`
   - Host: `hvnode02`
   - vCPU: 2
   - RAM: 4 GB
   - Storage: `CSV-Vol2` (show the CSV selection)
   - Network: Attach to `vSwitch-Workload`
3. Click **Create**
4. Watch VM appear in the VM list, boot up
5. Click **Connect** to open the in-browser console
6. **Talking point**: No VMConnect needed — browser-native console is part of WAC vMode

---

## Session 2 Walkthrough — SCVMM 2025

**Duration**: ~25 minutes  
**Console**: SCVMM Admin Console → `hvscvmm01.azrl.mgmt`

### Talking Points Opening (2 min)

- SCVMM 2025 for enterprise-scale Hyper-V management
- Logical networks abstract physical switch configuration
- Integration with System Center Suite and Azure

### Demo Step 1 — Fabric View (4 min)

1. Open SCVMM Admin Console → **Fabric** → **Servers**
2. Expand `hvlab-clus01` — show all 4 nodes with OverallState = **OK**
3. Click each node to show vCPU, memory, and storage capacity
4. Navigate to **Storage** — show the 3 CSVs and their capacity/usage
5. **Talking point**: SCVMM aggregates fabric inventory — SCVMM knows every NIC, every vSwitch, every storage path across all nodes

### Demo Step 2 — VM Deployment from Template (8 min)

1. Navigate to **VMs and Services** → **Create Virtual Machine**
2. Select an existing VM template (WS2022-Base or similar from the library)
3. Configure:
   - VM Name: `scvmm-demo-vm-01`
   - Destination: Cloud/Cluster `hvlab-clus01`
   - SCVMM will auto-select the least-loaded node
4. Show **Intelligent Placement** — SCVMM scores each node and picks the best
5. Click **Deploy**
6. Show deployment progress in the **Jobs** pane

### Demo Step 3 — Maintenance Mode (6 min)

1. Navigate to **Fabric** → **Servers** → right-click `hvnode04`
2. Select **Start Maintenance Mode**
3. Choose **Move all virtual machines to other nodes** → click **OK**
4. Watch the Jobs pane: each VM live-migrates away from `hvnode04`
5. Show `hvnode04` in Maintenance status
6. Right-click `hvnode04` → **Stop Maintenance Mode**
7. **Talking point**: This is the same workflow used before patching in production — drain the node, patch, return to service

### Demo Step 4 — Azure Integration (5 min)

1. Navigate to **Settings** → **Azure Management**
2. Show the subscription `00cd4357-ed45-4efb-bee0-10c467ff994b` connected
3. Show on-premises VMs alongside Azure VM inventory
4. **Talking point**: Unified inventory — one pane for hybrid workloads. SCVMM 2025 extends this to Azure Local cluster integration for a single management plane across on-premises and Azure

---

## What to Do If Something Breaks

### WAC vMode Web UI Unreachable

```powershell
# 1. Test from host VM
Test-NetConnection -ComputerName "172.16.10.30" -Port 443

# 2. RDP to hvwac01 via host VM (172.16.10.30)
# 3. Check services
Get-Service | Where-Object { $_.DisplayName -like "*Windows Admin Center*" -or
                              $_.Name -like "*postgres*" }
# 4. Start any stopped services
# 5. If TLS cert expired — see docs/09-wac-virtualization-mode.md troubleshooting
```

**Fallback**: Use WAC Administration Mode (installed on hv-host01 as backup) to at least show a Hyper-V management interface.

### Cluster Node Not Responding

```powershell
# From hv-host01
Restart-VM -Name "hvnode02" -Force
Start-Sleep 60
# Check it rejoined cluster
Get-ClusterNode -Cluster "hvlab-clus01" -Name "hvnode02"
```

**Fallback**: Continue demo with 3 nodes. Live migration and all scenarios still work.

### iSCSI Disconnected (CSV Offline)

```powershell
# Restart iSCSI initiator on affected node
Invoke-Command -ComputerName "hvnode02" -ScriptBlock {
    Restart-Service MSiSCSI -Force
    Start-Sleep 30
    Get-Disk | Where-Object BusType -eq "iSCSI" | Select-Object Number, HealthStatus
}
# If CSV comes back Online — continue demo
# If not — failover CSV ownership to another node
Move-ClusterSharedVolume -Name "CSV-Vol1" -Node "hvnode01"
```

### SCVMM Console Can't Connect

```powershell
# Test port from on-premises
Test-NetConnection -ComputerName "10.250.1.47" -Port 8100

# Restart SCVMM service on hvscvmm01
Invoke-Command -ComputerName "172.16.10.40" -ScriptBlock {
    Restart-Service vmmservice -Force
    Start-Sleep 30
    Get-Service vmmservice | Select-Object Name, Status
}
```

**Fallback**: Use PowerShell (`Import-Module VirtualMachineManager`) to demonstrate the same scenarios via script if the GUI is unavailable.

---

## Backup Plan — Screenshots and Recording

If a complete environment failure occurs (host VM unreachable, networking down), use the pre-recorded materials:

| Asset | Location | Contents |
|-------|----------|---------|
| WAC vMode recording | `scripts/demo/recordings/wac-vmode-full.mp4` | Complete Session 1 walkthrough |
| SCVMM recording | `scripts/demo/recordings/scvmm-full.mp4` | Complete Session 2 walkthrough |
| Architecture screenshots | `scripts/demo/screenshots/` | Architecture diagrams, cluster health |

**Presenter note**: If using the backup recording, narrate over it live. Focus the commentary on the architecture diagrams and talking points — the audience learns more from your explanation than from watching a perfect UI recording.

---

## Post-Demo

After the demo session:

1. **Debrief**: Note any questions that came up for the FAQ / future sessions
2. **Restore checkpoint** (optional): Trigger `hvlab-07-demo-reset.yml` to clean up any VMs created during the demo
3. **Deallocate the host VM** (if not needed for more sessions):

```powershell
az vm deallocate `
  --name "hv-host01" `
  --resource-group "rg-hvlab-mms26-eus-01"
```

> Deallocation stops billing for compute (~$10/hour). Storage costs continue. Restart when needed — the DEMO-READY checkpoint will be preserved on the managed data disk.
