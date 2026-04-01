# Compliance & Reporting

## Reporting Tools (Cheapest First)

| Tool | Cost | Best For |
|------|------|----------|
| Azure Resource Graph | Free | Cross-subscription compliance snapshots |
| Azure Update Manager Overview | Free | At-a-glance compliance dashboard |
| Azure Policy | Free (built-in policies) | Enforcement + compliance reporting |
| Azure Monitor Workbooks | Log Analytics ingestion cost | Custom dashboards |
| Log Analytics (KQL) | Per-GB ingestion | Deep diagnostics, forensics |

**Use Resource Graph first. Escalate to Log Analytics only when needed.**

## Azure Resource Graph Queries

See `../queries/resource-graph/` for ready-to-use queries.

Key queries:
- Machines with pending critical updates
- Machines not assessed in the last 7 days (agent health canary)
- Cross-resource compliance (Azure VMs + Arc servers)
- Hotpatch enrollment status across fleet

## Azure Policy for Updates

Key built-in policies:
- **"Periodic assessment should be enabled on your machines"** — audit or DeployIfNotExists
- **"System updates should be installed on your machines"** — audit compliance
- **"Machines should be configured to periodically check for missing system updates"** — enforcement

Use **DeployIfNotExists** policies to automatically configure assessment on new machines.

## Cost Model

| Item | Cost | Notes |
|------|------|-------|
| Azure Update Manager (Azure VMs) | Free | |
| Azure Update Manager (Arc servers) | ~$5/server/month | |
| Hotpatching (Arc on-prem) | ~$1.50/core/month | |
| Log Analytics ingestion | ~$2.76/GB | Basic Logs tier is cheaper |
| Resource Graph queries | Free | Best starting point |
| Azure Policy (built-in) | Free | Custom policies also free |

### Hidden Cost: Log Analytics Ingestion

If you enable full diagnostics and pipe everything to Log Analytics, ingestion costs can exceed the Update Manager cost. Be selective:
- Use Resource Graph for compliance (free)
- Use Log Analytics for deep troubleshooting only
- Use Basic Logs tier for high-volume data
- Set 30-day retention (not 90)
