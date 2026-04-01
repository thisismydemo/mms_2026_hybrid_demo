# Azure Local Update Management

## Azure Local Is Not a Server

Azure Local is a **solution** — a coordinated stack of:
- Operating system
- Azure Arc agents and services
- Cluster services (Storage Spaces Direct, failover clustering)
- Solution Builder Extension (SBE) — OEM-specific drivers and firmware

All layers must be updated together through the **Lifecycle Manager**, not individually.

## Supported Update Path

Updates are managed through **Azure Update Manager → Azure Local** or **Azure Arc → Azure Local → Updates**.

The Lifecycle Manager orchestrates:
1. Download update packages
2. Run readiness checks (cluster health, storage health, quorum)
3. Apply updates to one node at a time (rolling update)
4. Validate each node before proceeding to the next
5. Apply SBE (OEM firmware/drivers) if available

## Unsupported Update Methods

**Do NOT use these on Azure Local cluster nodes:**
- WSUS
- SCCM / ConfigMgr
- Manual Windows Update (`wuauclt`, Settings app)
- Direct KB installation via `wusa.exe`

These bypass the Lifecycle Manager and can leave the cluster in an inconsistent or unsupported state.

## Update Types

| Type | Cadence | Content |
|------|---------|---------|
| Feature release | ~Annually | Major version (e.g., 2504) |
| Cumulative update | Monthly | Security + quality fixes |
| Solution Builder Extension (SBE) | Vendor-dependent | OEM drivers, firmware, BIOS |

## Readiness Checks

Always run readiness checks before starting an update:
- Cluster health (all nodes online)
- Storage health (Storage Spaces Direct healthy)
- Quorum status
- SBE compatibility
- Sufficient disk space

**If anything is yellow or red — stop. Fix it first.**

## Cluster Updates vs. Guest VM Updates

| Aspect | Cluster Infrastructure | Guest VMs |
|--------|----------------------|-----------|
| What | OS, agents, firmware, SBE | Guest OS patches |
| How | Lifecycle Manager | Azure Update Manager (individually) |
| When | Maintenance window, rolling | Separate maintenance window |
| Rule | **Never run both at the same time** | |

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Update stuck at download | Connectivity from cluster to Azure | Check outbound internet |
| Readiness check fails | Unhealthy node or storage | Fix health issue first |
| SBE not available | OEM hasn't released package | Wait — don't force the update |
| Node fails to rejoin after update | Network or storage issue | Check cluster events, validate network |
