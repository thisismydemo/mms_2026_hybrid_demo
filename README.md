# The Hybrid Update Blues — MMS MOA 2026

End-to-end demo repository for the **"The Hybrid Update Blues: Patching Everything from Cloud to Closet"** session at MMS MOA 2026. Covers Azure Update Manager, Azure Arc onboarding, Azure Local update management, hotpatching on Windows Server 2025, and compliance reporting — all from a single pane of glass.

## Prerequisites

| Requirement | Details |
|---|---|
| Azure subscription | With Contributor access |
| Azure CLI | 2.60+ with `connectedmachine`, `maintenance` extensions |
| Azure Arc-enabled servers | 2+ on-prem or lab machines onboarded to Arc |
| Azure VMs | 2+ running Windows Server 2022/2025 |
| Azure Local cluster | (optional) For Demo 3 — Azure Local update management |
| Windows Server 2025 | For hotpatching demo (Demo 4) |

## Repository Structure

```text
├── Demo-Guide-Hybrid-Update-Blues.md   # Master demo guide — every slide + walkthrough
├── README.md                           # This file
├── presenter/
│   ├── run-of-show.md                  # Minute-by-minute timing plan
│   ├── slide-map.md                    # Slide-to-demo mapping
│   ├── fallback-plan.md                # What to do when things go wrong
│   └── day-of-checklist.md             # Morning-of verification checklist
├── docs/
│   ├── 01-overview.md                  # Session overview and goals
│   ├── 02-azure-update-manager.md      # AUM deep dive
│   ├── 03-arc-onboarding.md            # Arc onboarding steps
│   ├── 04-azure-local-updates.md       # Azure Local update management
│   ├── 05-hotpatching.md               # Hotpatch on Windows Server 2025
│   ├── 06-compliance-reporting.md      # Policy + compliance dashboards
│   ├── 07-cost-model.md                # Pricing breakdown
│   └── 08-troubleshooting.md           # Common issues and fixes
├── scripts/
│   ├── 01-prepare-demo-environment.ps1 # Validate environment readiness
│   ├── 02-create-maintenance-configurations.ps1
│   ├── 03-tag-update-rings.ps1         # Tag machines with UpdateRing
│   ├── 04-export-update-compliance.ps1 # Export compliance to CSV
│   ├── 05-validate-hotpatch-readiness.ps1
│   └── 06-collect-demo-artifacts.ps1   # Gather fallback artifacts
├── queries/
│   ├── resource-graph/
│   │   ├── pending-critical-updates.kql
│   │   ├── not-assessed-last-7-days.kql
│   │   └── arc-vs-azurevm-compliance.kql
│   └── log-analytics/                  # Future KQL queries
├── policy/
│   ├── built-in-policy-reference.md    # Policy definitions used in demo
│   ├── assignment-plan.md              # Step-by-step assignment guide
│   └── remediation-notes.md            # Remediation tips and gotchas
└── assets/
    ├── README.md                       # Asset naming conventions
    ├── diagrams/                       # Architecture diagrams
    ├── screenshots/                    # Portal screenshots for fallback
    └── recordings/                     # Screen recordings as backup
```

## Quick Start

```powershell
# 1. Validate your demo environment
.\.scripts\01-prepare-demo-environment.ps1 -SubscriptionId "2caa0b8a-a1d6-4f0c-8c03-861787b8315c" -ResourceGroupName "rg-c01-azl-eus-01"

# 2. Create maintenance configurations
.\.scripts\02-create-maintenance-configurations.ps1 -SubscriptionId "2caa0b8a-a1d6-4f0c-8c03-861787b8315c" -ResourceGroupName "rg-c01-azl-eus-01"

# 3. Tag machines for dynamic scoping
.\.scripts\03-tag-update-rings.ps1 -SubscriptionId "2caa0b8a-a1d6-4f0c-8c03-861787b8315c" -ResourceGroupName "rg-c01-azl-eus-01" -Ring "Ring1"

# 4. Collect fallback artifacts
.\.scripts\06-collect-demo-artifacts.ps1 -SubscriptionId "2caa0b8a-a1d6-4f0c-8c03-861787b8315c" -ResourceGroupName "rg-c01-azl-eus-01"
```

## Demo Flow (5 Demos, ~17 Minutes)

| # | Demo | Duration | Key Tool |
|---|---|---|---|
| 1 | Azure Update Manager Overview | ~4 min | Azure Update Manager blade |
| 2 | Arc Onboarding & Update Readiness | ~3 min | Arc-enabled servers, Resource Graph |
| 3 | Azure Local Update Management | ~4 min | Azure Update Manager → Azure Local |
| 4 | Hotpatching on Windows Server 2025 | ~3 min | Arc server, Hotpatch blade |
| 5 | Compliance & Reporting | ~3 min | Azure Policy, Resource Graph, Cost Analysis |

See [Demo-Guide-Hybrid-Update-Blues.md](Demo-Guide-Hybrid-Update-Blues.md) for the full walkthrough.

## Supporting Infrastructure vs. Demo Content

This repo separates **what must be running before the session starts** from **what is deployed or shown live**.

### Supporting Infrastructure — Deploy Before the Session

These components must be deployed and validated **days before** MMS MOA 2026. They are not live-deployed on stage.

| Component | Location | Purpose |
|---|---|---|
| Azure Local cluster (`tplabs-clus01`) | Pre-existing — do not redeploy | Provides the on-premises compute substrate |
| Arc-enrolled demo VMs | `scripts/01-prepare-demo-environment.ps1` | Verify Arc-enrolled machines are healthy before demos |
| Maintenance configurations | `scripts/02-create-maintenance-configurations.ps1` | Pre-create Ring 1/2/Defender configs |

```powershell
# Pre-session setup:
.\scripts\01-prepare-demo-environment.ps1
.\scripts\02-create-maintenance-configurations.ps1
.\scripts\03-tag-update-rings.ps1
```

### Demo Content — Shown Live

These are portal walkthroughs, KQL queries, and policy actions demonstrated on stage against the pre-deployed infrastructure.

| Demo | Tool | Script / Query |
|---|---|---|
| 1 — Azure Update Manager overview | Azure Portal | — |
| 2 — Arc onboarding & update readiness | Arc blade, Resource Graph | `queries/resource-graph/not-assessed-last-7-days.kql` |
| 3 — Azure Local update management | Azure Update Manager | `queries/resource-graph/pending-critical-updates.kql` |
| 4 — Hotpatching on WS2025 | Arc hotpatch blade | `scripts/05-validate-hotpatch-readiness.ps1` |
| 5 — Compliance & reporting | Azure Policy, Resource Graph | `queries/resource-graph/arc-vs-azurevm-compliance.kql` |

## Presenter Resources

- [Run of Show](presenter/run-of-show.md) — Timing plan for the full session
- [Slide Map](presenter/slide-map.md) — Which slides lead into which demos
- [Fallback Plan](presenter/fallback-plan.md) — Contingency for demo failures
- [Day-of Checklist](presenter/day-of-checklist.md) — Morning verification steps

## Cleanup

After the session, remove demo resources:

```powershell
# Remove demo-specific resource groups (does NOT delete the pre-existing cluster)
az group delete --name "rg-arc-demo" --subscription "00cd4357-ed45-4efb-bee0-10c467ff994b" --yes --no-wait
az group delete --name "rg-arc-test-vms" --subscription "2caa0b8a-a1d6-4f0c-8c03-861787b8315c" --yes --no-wait
```

## License

This repository is for demo and educational purposes at MMS MOA 2026.
