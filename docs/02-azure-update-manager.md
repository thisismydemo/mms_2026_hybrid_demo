# Azure Update Manager

## What It Is

Azure Update Manager is an **orchestration layer** that:
- Schedules update installations across Azure VMs and Arc-enabled servers
- Assesses machines for missing updates
- Reports compliance status
- Supports maintenance windows with reboot controls
- Uses dynamic scoping via tags

## What It Is Not

- Not a patch repository (it uses Windows Update, WSUS, or Linux package managers as the source)
- Not a replacement for Windows Update — it orchestrates it
- Not a WSUS replacement for content hosting — only for scheduling and compliance

## Key Capabilities

- **Maintenance Configurations**: Schedule-based update windows with classification filters
- **Dynamic Scoping**: Tag-based machine targeting (e.g., `UpdateRing = Ring1`)
- **Assessment**: On-demand or periodic scan for missing updates
- **One-Time Updates**: Ad hoc patching outside scheduled windows
- **Update History**: Full audit trail per machine
- **Multi-OS**: Windows and Linux support

## Maintenance Configuration Setup

1. Navigate to **Azure Update Manager → Maintenance Configurations → Create**
2. Set schedule: recurrence, day, time, timezone
3. Set classifications: Critical, Security, Update Rollup, etc.
4. Set reboot behavior: If Required / Always / Never
5. Set maintenance window duration
6. Add dynamic scopes with tag filters
7. Optionally add static machine assignments

## Pricing

| Resource Type | Cost |
|--------------|------|
| Azure VMs | Free |
| Arc-enabled servers | ~$5/server/month |
| Azure Local guest VMs (Arc-enabled) | ~$5/server/month |
