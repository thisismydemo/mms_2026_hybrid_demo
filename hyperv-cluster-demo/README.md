# Hyper-V Cluster Demo — MMS MOA 2026

This repository contains everything needed to deploy and operate a **nested Hyper-V failover cluster** running inside a single Azure VM. The environment is purpose-built for the MMS MOA 2026 demo showcasing Windows Admin Center Virtualization Mode, SCVMM 2025, Failover Clustering, and live migration — all reachable from an on-premises Azure Local cluster via BGP-advertised routing.

---

## What This Demo Does

- Provisions a `Standard_E104ids_v5` Azure VM (104 vCPU / 672 GB RAM / isolated hardware) in the existing `snet-lab-prodtech-eus-connectivity-mgmt` subnet
- Builds **9 nested VMs** inside that host using Hyper-V (DC, iSCSI target, 4 cluster nodes, WAC vMode server, SCVMM server)
- Forms a 4-node Failover Cluster (`hvlab-clus01`) with 3 × 500 GB iSCSI CSVs and Azure Blob Cloud Witness
- Installs **WAC Virtualization Mode** (WS2025, PostgreSQL backend) for fabric-level management
- Installs **SCVMM 2025** with SQL Server Developer for enterprise cluster management
- All nested VMs are reachable from on-prem / Azure Local via the existing BGP route advertisement (no new VNet or peering required)

---

## Architecture Summary

```
Azure Subscription 00cd4357-ed45-4efb-bee0-10c467ff994b
  Resource Group: rg-hvlab-mms26-eus-01
    Host VM: hv-host01  10.250.2.5  (Standard_E104ids_v5)
      ├── hvdc01       172.16.10.10   AD Replica DC
      ├── hviscsi01    172.16.30.10   iSCSI Target
      ├── hvnode01-04  172.16.10.21-24  Cluster Nodes
      ├── hvwac01      172.16.10.30 + secondary 10.250.2.6  WAC vMode (WS2025)
      └── hvscvmm01    172.16.10.40 + secondary 10.250.2.7  SCVMM 2025
```

> BGP: FortiGate-90G (ASN 65421) ↔ Azure VPN GW (ASN 65422) — 10.250.0.0/16 advertised on-prem, so nested VMs with secondary IPs in this range are reachable directly.

---

## Quick Start

### Prerequisite Checklist

Before running any workflow, complete **all** steps in [`docs/02-prerequisites.md`](docs/02-prerequisites.md):

- [ ] Run `00-setup-identity.ps1` once to create `mi-hvlab-deploy-eus-01` and set GitHub secrets (no app registration needed)
- [ ] Key Vault secrets pre-staged (9 secrets — see prerequisites doc)
- [ ] GitHub runner token ready (for workflow 02)
- [ ] WS2022 and WS2025 evaluation ISO files uploaded to blob storage
- [ ] Domain admin credentials available for `azrl.mgmt`

### Deployment Sequence

| Step | Workflow | Description | Est. Time |
|------|----------|-------------|-----------|
| 1 | `hvlab-01-host-vm.yml` | Deploy host VM via Bicep | 10 min |
| 2 | `hvlab-02-runner-bootstrap.yml` | Install GitHub Actions runner on host | 5 min |
| — | *Wait* | Runner label `hvlab-host` appears as **Online** in GitHub | — |
| 3 | `hvlab-03-configure-host.yml` | Install Hyper-V, configure vSwitches | 15 min |
| 4 | `hvlab-04-nested-vms.yml` | Create and boot nested VMs | 45 min |
| 5 | `hvlab-05-ad-cluster.yml` | Configure DC, join domain, form cluster | 30 min |
| 6 | `hvlab-06-wac-scvmm.yml` | Install WAC vMode and SCVMM 2025 | 60 min |
| — | Checkpoint | Trigger `hvlab-07-demo-reset.yml` → creates DEMO-READY checkpoint | 20 min |

**Total deployment time: approximately 3 hours.**

---

## Documentation

| Doc | Description |
|-----|-------------|
| [01-architecture-overview.md](docs/01-architecture-overview.md) | Full architecture, IP diagram, connection paths |
| [02-prerequisites.md](docs/02-prerequisites.md) | Everything to do before running workflow 01 |
| [03-host-vm-sizing.md](docs/03-host-vm-sizing.md) | Why E104ids_v5, vCPU/RAM math, NVMe tip |
| [04-networking.md](docs/04-networking.md) | vSwitch layout, WinNAT, secondary IP forwarding |
| [05-active-directory.md](docs/05-active-directory.md) | Domain join, replica DC, OUs, service accounts |
| [06-iscsi-storage.md](docs/06-iscsi-storage.md) | iSCSI Target role, MPIO, LUN layout |
| [07-hyper-v-cluster.md](docs/07-hyper-v-cluster.md) | Failover Cluster setup, CSVs, Cloud Witness |
| [08-cloud-witness.md](docs/08-cloud-witness.md) | Cloud Witness config and graceful degradation |
| [09-wac-virtualization-mode.md](docs/09-wac-virtualization-mode.md) | WAC vMode full install guide ⭐ |
| [10-scvmm-setup.md](docs/10-scvmm-setup.md) | SCVMM 2025 + SQL Server Developer install |
| [11-bgp-routing-connectivity.md](docs/11-bgp-routing-connectivity.md) | BGP deep dive, secondary IP forwarding |
| [12-deployment-workflow.md](docs/12-deployment-workflow.md) | Step-by-step deployment with troubleshooting |
| [13-demo-day-guide.md](docs/13-demo-day-guide.md) | Demo day checklist and session walkthroughs |

---

## Demo Day Instructions

### Restoring the DEMO-READY Checkpoint

If anything goes wrong before or during the demo, restore the environment to a known-good state:

1. In GitHub Actions, navigate to **Actions → hvlab-07-demo-reset**
2. Click **Run workflow** → select branch `main` → click **Run workflow**
3. Wait ~20 minutes for all nested VMs to revert to the `DEMO-READY` checkpoint
4. Verify using the checklist in [`docs/13-demo-day-guide.md`](docs/13-demo-day-guide.md)

### Session Overview

| Session | Tool | Key Scenarios |
|---------|------|---------------|
| Session 1 | WAC Virtualization Mode | Live migration, VM creation, host health dashboard |
| Session 2 | SCVMM 2025 | VM deployment, cluster management, Azure integration |

> **Critical reminder**: WAC Virtualization Mode (`hvwac01`) runs on **WS2025** and is a completely different product from WAC Administration Mode. Do not confuse them during the presentation.

---

## Repository Structure

```
hyperv-cluster-demo/
├── README.md                    ← This file
├── bicep/
│   ├── main.bicep               ← Host VM + NIC + secondary IPs
│   └── parameters/
│       ├── prod.bicepparam
│       └── dev.bicepparam
├── config/
│   ├── vswitches.json
│   └── nested-vms.json
├── scripts/
│   ├── deploy/                  ← Called by Custom Script Extension
│   ├── configure/               ← Post-deploy configuration
│   ├── nested-vms/              ← Nested VM creation and configuration
│   └── demo/                    ← Demo reset and checkpoint scripts
└── docs/                        ← All documentation (this folder)
```

---

## Support

- **Event contact**: MMS MOA 2026 lab team
- **Subscription**: `00cd4357-ed45-4efb-bee0-10c467ff994b`
- **Resource Group**: `rg-hvlab-mms26-eus-01`
- **GitHub runner label**: `hvlab-host`
