# Overview — The Hybrid Update Blues

## Session Purpose

This session covers hybrid update management across Azure VMs, Arc-enabled on-prem servers, and Azure Local clusters using Azure Update Manager as the single control plane.

## Key Themes

1. **Azure Update Manager** is the unified orchestration layer — not a patch host, not a replacement for Windows Update, but the scheduling and compliance layer on top.
2. **Azure Arc** is the on-ramp for on-prem servers — it projects them into Azure as ARM resources so they can be managed identically to Azure VMs.
3. **Azure Local** cluster updates are fundamentally different from server updates — they are coordinated solution updates across OS + agents + services + OEM firmware.
4. **Hotpatching** reduces reboots to 4 per year (baseline months) instead of 12.
5. **Compliance and reporting** should use Azure Resource Graph (free) before reaching for Log Analytics (paid).

## Update Engine Landscape

| Engine | Scope | Control |
|--------|-------|---------|
| Windows Update Agent | Individual OS updates | Local or WSUS/AUM-directed |
| Azure Update Manager | Scheduling, orchestration, compliance | Azure portal / API |
| Azure Local Lifecycle Manager | Coordinated cluster solution updates | Azure portal (not WSUS/SCCM) |
| WSUS | Legacy approval workflow | Being sunset — migrate to AUM |
| SCCM / Intune | Endpoint management | Complementary, not competing |
| Third-party tools | Linux, firmware, app updates | Varies by vendor |

## Cost Model Summary

| Item | Cost |
|------|------|
| Azure Update Manager for Azure VMs | Free |
| Azure Update Manager for Arc-enabled servers | ~$5/server/month |
| Hotpatching for Azure VMs (Azure Edition) | Free |
| Hotpatching for Arc-enabled on-prem servers | ~$1.50/core/month |
| Azure Resource Graph queries | Free |
| Log Analytics ingestion | Per GB — be selective |
