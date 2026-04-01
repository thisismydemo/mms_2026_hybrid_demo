# Fallback Plan — The Hybrid Update Blues

Every demo has a fallback. Screenshots and recordings live in `../assets/`.

## Demo 1: Azure Update Manager Overview

| Failure | Fallback |
|---------|----------|
| Portal slow or down | Screenshot: `assets/screenshots/demo1-aum-overview.png` |
| No machines appear | Check subscription filter; switch to screenshot |
| Maintenance config missing | Screenshot: `assets/screenshots/demo1-maintenance-config.png` |

## Demo 2: Arc Onboarding & Update Readiness

| Failure | Fallback |
|---------|----------|
| Arc server disconnected | Use it as a teaching moment — "this is exactly what broken looks like" |
| Resource Graph query fails | Screenshot: `assets/screenshots/demo2-resource-graph.png` |
| Agent version not visible | Screenshot: `assets/screenshots/demo2-arc-agent.png` |

## Demo 3: Azure Local Update Management

| Failure | Fallback |
|---------|----------|
| No Azure Local cluster accessible | Screenshot or recording — this is the most likely fallback |
| Update history empty | Show available updates and readiness checks instead |
| Readiness check fails | Use it as a teaching moment — "this is why you always run checks first" |

**This is the most environment-dependent demo.**

## Demo 4: Hotpatching

| Failure | Fallback |
|---------|----------|
| Machine not enrolled | Walk through enrollment live — it's just a checkbox |
| No hotpatch history | Screenshot: `assets/screenshots/demo4-hotpatch-history.png` |
| Machine is Azure VM not Arc | Still show it — feature is the same, cost model differs |

## Demo 5: Compliance & Reporting

| Failure | Fallback |
|---------|----------|
| Resource Graph returns empty | Screenshot: `assets/screenshots/demo5-resource-graph.png` |
| Policy compliance not populated | Screenshot: `assets/screenshots/demo5-policy-compliance.png` |
| Cost Management inaccessible | Screenshot: `assets/screenshots/demo5-cost-analysis.png` |

## General Rules

1. Never apologize — just switch to "Let me show you what this looks like" and use the screenshot.
2. Backup PowerPoint with embedded screenshots covers the worst case.
3. Capture screenshots at 125–150% zoom, 1920×1080 minimum.
4. Record 30–60 sec clips of each demo as last-resort fallback.
