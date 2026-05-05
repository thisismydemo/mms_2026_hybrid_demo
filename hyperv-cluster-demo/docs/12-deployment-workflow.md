# 12 — Deployment Workflow

## Overview

Deployment uses a two-phase pipeline:

1. **Cloud GitHub Actions runners** (phases 1–2): Deploy the Azure infrastructure and bootstrap the self-hosted runner
2. **Self-hosted runner on host VM** (phases 3–8): All nested VM and application configuration — runs directly on the host, with access to the Hyper-V APIs and nested VM networks

---

## Pre-Flight Checks

Complete these checks immediately before starting deployment:

```powershell
# 1. Azure CLI authenticated to correct subscription
az account show --query "{sub:id, state:state}" -o table
# Expected: 00cd4357-ed45-4efb-bee0-10c467ff994b, Enabled

# 2. Target IPs available
foreach ($ip in @("10.250.1.45","10.250.1.46","10.250.1.47")) {
    $used = az network nic list --query "[].ipConfigurations[?privateIPAddress=='$ip'].privateIPAddress" -o tsv
    if ($used) { Write-Host "✗ $ip IN USE" -ForegroundColor Red }
    else        { Write-Host "✓ $ip available" -ForegroundColor Green }
}

# 3. Key Vault secrets present (run the verification block from 02-prerequisites.md)

# 4. Subnet exists
az network vnet subnet show `
  --name "snet-lab-prodtech-eus-connectivity-mgmt" `
  --vnet-name "vnet-lab-prodtech-eus-connectivity-hub" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --query "{name:name, prefix:addressPrefix}" -o table

# 5. GitHub runner token freshness — regenerate if >45 min old
# Navigate to: GitHub → Repo Settings → Actions → Runners → New self-hosted runner
# Copy the token and update: kv-hvlab-mms26-eus-01 / hvlab-github-runner-token
```

---

## Workflow 01 — Deploy Host VM

**Workflow**: `hvlab-01-host-vm.yml`  
**Runs on**: GitHub-hosted runner (`ubuntu-latest`)  
**Estimated time**: 10–15 minutes

### What It Does

1. Logs in to Azure using `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_SECRET`
2. Runs `az deployment group create` with `bicep/main.bicep`
3. Creates:
   - NIC `nic-hv-host01` with 3 IP configurations (`.45`, `.46`, `.47`)
   - IP forwarding enabled on NIC
   - VM `hv-host01` (Standard_E104ids_v5)
   - OS disk (P10, 128 GB)
   - Data disk for VHDX storage (P50, 4 TB)
4. Attaches a Custom Script Extension that installs the GitHub Actions runner prerequisites

### Trigger

```yaml
# Manually trigger from GitHub Actions UI:
# Actions → hvlab-01-host-vm → Run workflow → main → Run workflow
```

### Verify Success

```powershell
# Check VM state
az vm show `
  --name "hv-host01" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --query "{name:name, state:powerState, size:hardwareProfile.vmSize}" -o table

# Check NIC secondary IPs
az network nic show `
  --name "nic-hv-host01" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --query "ipConfigurations[].{name:name, ip:privateIPAddress}" -o table

# Test connectivity
Test-Connection -ComputerName "10.250.1.45" -Count 4
```

### Common Failures

| Failure | Cause | Fix |
|---------|-------|-----|
| `QuotaExceeded` | E104ids_v5 capacity unavailable | Request quota increase or use fallback SKU from `docs/03-host-vm-sizing.md` |
| `IPAddressAlreadyInUse` | `.45`/`.46`/`.47` allocated | Check existing NICs and release the IP |
| `AuthorizationFailed` | Service principal missing Contributor role | `az role assignment create --role Contributor ...` |

---

## Workflow 02 — Bootstrap Self-Hosted Runner

**Workflow**: `hvlab-02-runner-bootstrap.yml`  
**Runs on**: GitHub-hosted runner (`ubuntu-latest`)  
**Estimated time**: 5 minutes

### What It Does

1. Retrieves the runner token from Key Vault (`hvlab-github-runner-token`)
2. Uses Azure VM Run Command to execute the runner installation script on `hv-host01`
3. The script installs the GitHub Actions runner service with label `hvlab-host`

### ⚠️ Token Expiry Warning

The runner registration token expires **1 hour** after generation. If workflow 02 runs more than 1 hour after the token was stored in Key Vault:

```powershell
# Regenerate token and update Key Vault
$newToken = "<new-token-from-github-settings>"
az keyvault secret set `
  --vault-name "kv-hvlab-mms26-eus-01" `
  --name "hvlab-github-runner-token" `
  --value $newToken
```

### Verify Success

In GitHub: **Settings → Actions → Runners** — the runner `hv-host01` should appear with label `hvlab-host` and status **Idle**.

Allow up to 3 minutes after workflow completion for the runner to appear.

---

## Wait for Runner Online

**Do not proceed to workflow 03** until the runner appears as **Idle** (not Offline) in GitHub.

Check: `https://github.com/<org>/<repo>/settings/actions/runners`

If the runner shows as **Offline** after 5 minutes:

```powershell
# RDP to hv-host01 (10.250.1.45) and check
# On the host VM:
Get-Service -Name "actions.runner.*" | Select-Object Name, Status
Start-Service -Name "actions.runner.*"

# Check runner logs
Get-Content "C:\actions-runner\_diag\Runner_*.log" -Tail 50
```

---

## Workflow 03 — Configure Host

**Workflow**: `hvlab-03-configure-host.yml`  
**Runs on**: `hvlab-host` (self-hosted)  
**Estimated time**: 15–20 minutes (includes reboot)

### What It Does

1. Installs `Hyper-V` Windows feature with management tools
2. Installs `RSAT-Hyper-V-Tools`
3. Reboots the host VM (runner auto-reconnects after reboot)
4. Creates all 6 vSwitches (`vSwitch-External`, `vSwitch-Mgmt`, `vSwitch-Migration`, `vSwitch-Storage`, `vSwitch-Heartbeat`, `vSwitch-Workload`)
5. Configures WinNAT for `172.16.10.0/24`
6. Enables IP routing on the host OS
7. Joins `hv-host01` to the `azrl.mgmt` domain (requires `hvlab-domain-admin-*` secrets)
8. Reboots after domain join

### Verify Success

```powershell
# On host VM — check Hyper-V installed
Get-WindowsFeature -Name Hyper-V | Select-Object Name, InstallState

# Check vSwitches
Get-VMSwitch | Select-Object Name, SwitchType, NetAdapterInterfaceDescription

# Check domain join
(Get-WmiObject Win32_ComputerSystem).Domain  # Should be azrl.mgmt

# Check WinNAT
Get-NetNat | Select-Object Name, InternalIPInterfaceAddressPrefix
```

---

## Workflow 04 — Create Nested VMs

**Workflow**: `hvlab-04-nested-vms.yml`  
**Runs on**: `hvlab-host`  
**Estimated time**: 45–60 minutes

### What It Does

1. Downloads WS2022 and WS2025 ISOs from `sthvlabisomms26` blob storage
2. Creates base VHDX files on the data disk
3. Creates and configures all 8 nested VMs with correct vCPU, RAM, vNICs, and attached ISOs
4. Boots VMs in order: `hvdc01` first, then storage, then nodes, then management VMs
5. Applies unattend.xml for automated OS installation
6. Waits for VMs to complete OS installation (polls WinRM)

### Verify Success

```powershell
# On host VM
Get-VM | Select-Object Name, State, CPUCount,
    @{N="RAM-GB";E={$_.MemoryAssigned/1GB}} |
    Format-Table -AutoSize

# Expected: 8 VMs, all Running
```

---

## Workflow 05 — AD and Cluster Setup

**Workflow**: `hvlab-05-ad-cluster.yml`  
**Runs on**: `hvlab-host`  
**Estimated time**: 30–40 minutes

### What It Does (in order)

1. Promotes `hvdc01` as replica DC for `azrl.mgmt`
2. Waits for AD replication to complete
3. Creates OU structure, service accounts, security groups (from `docs/05-active-directory.md`)
4. Joins all nested VMs to `azrl.mgmt`
5. Configures iSCSI Target on `hviscsi01` (from `docs/06-iscsi-storage.md`)
6. Installs Failover Clustering and Hyper-V roles on `hvnode01-04`
7. Configures MPIO on cluster nodes
8. Connects iSCSI initiators on all nodes
9. Creates cluster `hvlab-clus01`
10. Adds CSVs and configures Cloud Witness
11. Configures KCD for live migration

### Verify Success

```powershell
# Check cluster health
Get-Cluster -Name "hvlab-clus01" | Select-Object Name, QuorumType
Get-ClusterNode -Cluster "hvlab-clus01" | Select-Object Name, State
Get-ClusterSharedVolume -Cluster "hvlab-clus01" | Select-Object Name, State
Get-ClusterQuorum -Cluster "hvlab-clus01"
```

---

## Workflow 06 — Install WAC vMode and SCVMM

**Workflow**: `hvlab-06-wac-scvmm.yml`  
**Runs on**: `hvlab-host`  
**Estimated time**: 60–90 minutes

### What It Does

1. On `hvwac01`:
   - Installs Visual C++ Redistributable (winget)
   - Downloads WAC vMode installer from `https://aka.ms/WACDownloadvMode`
   - Installs WAC vMode with PostgreSQL
   - Configures firewall rules
   - Adds cluster nodes as managed hosts

2. On `hvscvmm01`:
   - Downloads SQL Server 2022 Developer installer
   - Installs SQL Server with SCVMM named instance
   - Installs SCVMM 2025
   - Configures logical networks
   - Adds Hyper-V cluster to SCVMM

### Verify Success

```powershell
# Test WAC vMode HTTPS endpoint
Invoke-WebRequest -Uri "https://10.250.1.46" -SkipCertificateCheck -UseBasicParsing `
    -TimeoutSec 15 | Select-Object StatusCode

# Test SCVMM console port
Test-NetConnection -ComputerName "10.250.1.47" -Port 8100
```

---

## Create DEMO-READY Checkpoint

After workflow 06 completes successfully, create the DEMO-READY checkpoint immediately:

```powershell
# Trigger from GitHub Actions:
# Actions → hvlab-07-demo-reset → Run workflow → Run workflow
# (First run creates the checkpoint; subsequent runs restore it)
```

**Or manually from the host VM:**

```powershell
# On hv-host01 — create DEMO-READY checkpoints on all nested VMs
$vms = Get-VM
foreach ($vm in $vms) {
    Checkpoint-VM -VM $vm -SnapshotName "DEMO-READY"
    Write-Host "Checkpoint created: $($vm.Name)"
}
```

---

## Estimated Total Deployment Time

| Phase | Workflow | Time |
|-------|----------|------|
| Infrastructure | 01 | 15 min |
| Runner bootstrap | 02 | 5 min |
| Host configuration | 03 | 20 min |
| Nested VMs | 04 | 60 min |
| AD + Cluster | 05 | 40 min |
| WAC + SCVMM | 06 | 90 min |
| Checkpoint | 07 | 20 min |
| **Total** | | **~4 hours** |

---

## Re-Running a Failed Workflow

All workflows are designed to be idempotent — safe to re-run after a failure:

```powershell
# Before re-running: check what failed
# 1. Review the workflow run log in GitHub Actions
# 2. Identify the failing step name
# 3. If the failure is infrastructure (VM not created): fix the root cause and re-run 01
# 4. If the failure is in-guest (VM config): re-run the specific workflow; scripts check
#    for existing state before applying changes

# Common re-run scenarios:
# - Workflow 02 runner token expired: regenerate token → re-run 02
# - Workflow 04 ISO download failed: check blob storage → re-run 04
# - Workflow 05 domain join failed: verify DC replication → re-run 05
# - Workflow 06 WAC install failed: check WS2025 on hvwac01 → re-run 06
```

---

## Troubleshooting Reference

### Runner Goes Offline Mid-Workflow

```powershell
# On hv-host01 — check runner service
Get-Service -Name "actions.runner.*" | Select-Object Name, Status

# If stopped due to reboot:
Start-Service -Name "actions.runner.*"

# Re-trigger the workflow from GitHub Actions UI
```

### VM Won't Boot After Creation

```powershell
# On hv-host01
Get-VM -Name "hvdc01" | Select-Object Name, State, Status
# Check for "Critical" state — means VHDX issue

# Check VHDX integrity
Get-VHD -Path "D:\HyperV\hvdc01\hvdc01.vhdx" | Select-Object Path, IsAttached, LogicalSectorSize

# Check Hyper-V event log
Get-WinEvent -LogName "Microsoft-Windows-Hyper-V-VMMS-Admin" -MaxEvents 20 |
    Select-Object TimeCreated, Message
```

### Cluster Formation Fails on Validation

```powershell
# Re-run cluster validation with output
Test-Cluster -Node "hvnode01","hvnode02","hvnode03","hvnode04" `
  -ReportName "C:\ClusterValidation\recheck" 2>&1

# Open report
Start-Process "C:\ClusterValidation\recheck.htm"

# Common issues:
# - Storage: iSCSI not connected — re-run iSCSI initiator setup
# - Network: missing heartbeat network — check vSwitch-Heartbeat NIC on nodes
# - Hyper-V: feature not installed — re-run feature installation
```
