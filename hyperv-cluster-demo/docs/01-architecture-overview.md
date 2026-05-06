# 01 — Architecture Overview

## Summary

This environment is a nested Hyper-V lab running entirely inside a single Azure VM. The host VM sits in an existing Azure subnet that is BGP-advertised to on-premises, making every nested VM with a secondary IP in the `10.250.0.0/16` range directly reachable from the Azure Local cluster and the corporate network — no new VNet, no peering, no UDR.

---

## Host VM

| Property | Value |
|----------|-------|
| Azure VM name | `hv-host01` |
| SKU | `Standard_E104ids_v5` |
| vCPU | 104 |
| RAM | 672 GB |
| Local NVMe | ~3.8 TB (ephemeral — not for persistence) |
| Azure NIC IP | `10.250.2.5` (static, primary) |
| Secondary IP — WAC | `10.250.2.6` (mapped to `hvwac01`) |
| Secondary IP — SCVMM | `10.250.2.7` (mapped to `hvscvmm01`) |
| Subscription | `00cd4357-ed45-4efb-bee0-10c467ff994b` |
| Resource Group | `rg-hvlab-mms26-eus-01` |
| VNet | `vnet-lab-prodtech-eus-connectivity-hub` (`10.250.0.0/16`) |
| Subnet | `snet-lab-prodtech-eus-connectivity-mgmt` (`10.250.2.0/24`) |

---

## Nested VM Inventory

| VM | vCPU | RAM | IP (Mgmt vSwitch) | Secondary Azure IP | OS | Role |
|----|------|-----|--------------------|-------------------|-----|------|
| `hvdc01` | 2 | 8 GB | `172.16.10.10` | — | WS2022 | AD Replica DC |
| `hviscsi01` | 4 | 16 GB | `172.16.10.11` | — | WS2022 | iSCSI Target |
| `hvnode01` | 16 | 64 GB | `172.16.10.21` | — | WS2022 | Cluster Node 1 |
| `hvnode02` | 16 | 64 GB | `172.16.10.22` | — | WS2022 | Cluster Node 2 |
| `hvnode03` | 16 | 64 GB | `172.16.10.23` | — | WS2022 | Cluster Node 3 |
| `hvnode04` | 16 | 64 GB | `172.16.10.24` | — | WS2022 | Cluster Node 4 |
| `hvwac01` | 4 | 16 GB | `172.16.10.30` | `10.250.2.6` | **WS2025** | WAC vMode |
| `hvscvmm01` | 8 | 32 GB | `172.16.10.40` | `10.250.2.7` | WS2022 | SCVMM 2025 |

**Total nested vCPU**: 70 (of 104 available) | **Total nested RAM**: 296 GB (of 672 GB available)

---

## vSwitch Layout

Six virtual switches are configured on the host VM:

| vSwitch | Type | Network | Purpose |
|---------|------|---------|---------|
| `vSwitch-External` | External (bound to Azure NIC) | `10.250.2.0/24` | Nested VM Azure reachability / secondary IPs |
| `vSwitch-Mgmt` | Internal | `172.16.10.0/24` | Management traffic, domain join, RDP |
| `vSwitch-Migration` | Private | `172.16.20.0/24` | Live migration traffic |
| `vSwitch-Storage` | Private | `172.16.30.0/24` | iSCSI storage traffic (MPIO) |
| `vSwitch-Heartbeat` | Private | `172.16.40.0/24` | Cluster heartbeat |
| `vSwitch-Workload` | Private | `172.16.50.0/24` | Guest VM workload traffic |

> `vSwitch-External` is the only switch with a physical adapter binding. All other switches are internal or private to the host.

---

## IP Address Diagram

```
ON-PREMISES / AZURE LOCAL
  Azure Local cluster: 192.168.211.x
  FortiGate-90G: ASN 65421
          |
          | BGP tunnel (IPsec/VPN)
          |  Advertises: 10.250.0.0/16 → on-prem
          |              192.168.211.0/24 → Azure
          |
AZURE VPN GATEWAY: ASN 65422
          |
          | VNet: vnet-lab-prodtech-eus-connectivity-hub (10.250.0.0/16)
          |
SUBNET: snet-lab-prodtech-eus-connectivity-mgmt (10.250.2.0/24)
  ├── 172.16.10.10  DC1 (existing — azrl.mgmt)
  ├── 172.16.10.11  DC2 (existing — azrl.mgmt)
  ├── 10.250.2.5  hv-host01  ← HOST VM (Standard_E104ids_v5)
  ├── 10.250.2.6  → forwarded into host → hvwac01  (WS2025, WAC vMode)
  └── 10.250.2.7  → forwarded into host → hvscvmm01 (WS2022, SCVMM 2025)

INSIDE HOST VM (Hyper-V nested)
  vSwitch-Mgmt (172.16.10.0/24)
  ├── 172.16.10.10   hvdc01      (AD Replica DC)
  ├── 172.16.10.11   hviscsi01   (iSCSI Target)
  ├── 172.16.10.21   hvnode01    (Cluster Node 1)
  ├── 172.16.10.22   hvnode02    (Cluster Node 2)
  ├── 172.16.10.23   hvnode03    (Cluster Node 3)
  ├── 172.16.10.24   hvnode04    (Cluster Node 4)
  ├── 172.16.10.30   hvwac01     + vSwitch-External NIC → 10.250.2.6
  └── 172.16.10.40   hvscvmm01   + vSwitch-External NIC → 10.250.2.7

  vSwitch-Migration (172.16.20.0/24)
  └── hvnode01-04: .21-.24

  vSwitch-Storage (172.16.30.0/24)
  ├── hviscsi01:    .10 + .11  (dual-homed for MPIO)
  └── hvnode01-04:  .21-.24 (two NICs each, for MPIO paths)

  vSwitch-Heartbeat (172.16.40.0/24)
  └── hvnode01-04: .21-.24

  vSwitch-Workload (172.16.50.0/24)
  └── hvnode01-04: .21-.24
```

---

## Why the Existing Subnet Is Used

A new VNet or subnet is **not created** for this demo. The host VM is placed directly in the existing `snet-lab-prodtech-eus-connectivity-mgmt` subnet because:

1. **BGP route advertisement already exists**: FortiGate-90G (ASN 65421) peers with the Azure VPN Gateway (ASN 65422) and advertises `10.250.0.0/16` to on-premises. This means any IP in that range is routable from the Azure Local cluster and corporate network without any additional routing configuration.

2. **Secondary IPs inherit the advertisement**: When `10.250.2.6` and `10.250.2.7` are assigned as secondary IPs on the host's Azure NIC and forwarded into the nested VMs, those VMs become reachable from on-prem at those addresses automatically.

3. **Existing DCs are reachable**: `hvdc01` inside the nested environment needs to replicate with the existing DCs at `172.16.10.10` and `172.16.10.11`. Placing the host in the same subnet ensures low-latency, direct replication.

4. **No UDR required**: Because the route is BGP-advertised and the host VM is the destination for `.46`/`.47`, Azure's NIC-level IP forwarding handles the traffic. No User Defined Route table is needed.

See [`docs/11-bgp-routing-connectivity.md`](11-bgp-routing-connectivity.md) for a full BGP deep dive.

---

## Connection Paths

### From On-Premises / Azure Local to Nested VMs

| Source | Destination | Path |
|--------|-------------|------|
| Azure Local cluster (192.168.211.x) | `hv-host01` (10.250.2.5) | BGP → VPN GW → Azure VNet → Subnet |
| Azure Local cluster | `hvwac01` (10.250.2.6) | BGP → VPN GW → NIC secondary IP → IP forwarding → nested VM |
| Azure Local cluster | `hvscvmm01` (10.250.2.7) | BGP → VPN GW → NIC secondary IP → IP forwarding → nested VM |
| Azure Local cluster | `hvnode01-04` (172.16.10.x) | Not directly routable — manage via `hvwac01` or `hvscvmm01` |

### From Inside Host VM to Nested VMs

All nested VMs on `vSwitch-Mgmt` (172.16.10.0/24) are directly reachable from the host OS. The host acts as the gateway for the `172.16.10.0/24` range using WinNAT. See [`docs/04-networking.md`](04-networking.md).

### From Nested VMs to Azure / Internet

Nested VMs route outbound via WinNAT through the host's Azure NIC on `vSwitch-External`. This provides:
- Access to Azure services (Windows Update, Key Vault, storage accounts)
- Access to the internet for package downloads during setup

---

## Cluster Architecture

```
Failover Cluster: hvlab-clus01
  ├── hvnode01  (16 vCPU / 64 GB RAM)
  ├── hvnode02  (16 vCPU / 64 GB RAM)
  ├── hvnode03  (16 vCPU / 64 GB RAM)
  └── hvnode04  (16 vCPU / 64 GB RAM)

Shared Storage (iSCSI via hviscsi01):
  ├── CSV-Vol1  500 GB  — workload VMs
  ├── CSV-Vol2  500 GB  — workload VMs
  └── CSV-Vol3  500 GB  — workload VMs

Quorum:
  └── Cloud Witness → Azure Blob (sthvlabwitness01)

Management:
  ├── WAC Virtualization Mode  → hvwac01  (10.250.2.6)
  └── SCVMM 2025               → hvscvmm01 (10.250.2.7)
```

---

## Active Directory

- **Domain**: `azrl.mgmt`
- **Existing DCs**: `172.16.10.10`, `172.16.10.11` (do not modify)
- **Replica DC**: `hvdc01` inside the nested environment — required so that cluster nodes (on the isolated 172.16.x.x networks) can authenticate via Kerberos without depending on a WAN path to `172.16.10.10/.37`
- The host VM (`hv-host01`) joins `azrl.mgmt` using the existing DCs directly

---

## Deployment Pipeline

```
GitHub Actions (cloud runners)
  ├── hvlab-01-host-vm.yml        → Bicep deploy via Azure CLI
  └── hvlab-02-runner-bootstrap.yml → Install self-hosted runner (label: hvlab-host)

GitHub Actions (self-hosted runner: hvlab-host — runs ON the host VM)
  ├── hvlab-03-configure-host.yml  → Hyper-V role, vSwitches
  ├── hvlab-04-nested-vms.yml      → Create nested VMs
  ├── hvlab-05-ad-cluster.yml      → DC, domain join, cluster
  ├── hvlab-06-wac-scvmm.yml       → WAC vMode, SCVMM 2025
  └── hvlab-07-demo-reset.yml      → Restore DEMO-READY checkpoint
```
