# Repo intent — mms_2026_hybrid_demo

**MMS MOA 2026 session demo — "The Hybrid Update Blues: Patching Everything from Cloud to Closet."**

## What this repo is

End-to-end demo repository covering Azure Update Manager, Azure Arc onboarding,
Azure Local update management, hotpatching on Windows Server 2025, and compliance
reporting — all from a single pane of glass — for the MMS MOA 2026 session.

## Shape

- `Demo-Guide-Hybrid-Update-Blues.md` — master demo guide, every slide + walkthrough
- `presenter/` — run-of-show, slide-map, fallback-plan, day-of materials
- `hyperv-cluster-demo/`, `policy/`, `queries/`, `scripts/`
- Requires: Azure subscription (Contributor), Azure CLI 2.60+ with
  `connectedmachine`/`maintenance` extensions, 2+ Arc-onboarded machines, 2+ Azure
  VMs (Server 2022/2025), optional Azure Local cluster for Demo 3, Server 2025 for
  the hotpatching demo

## How it relates to other repos

- Sibling session-demo repo: **`mms_2026_avd_demo`** (same summit, different
  session)

## Status

Active — built for a specific 2026 conference session; check the presenter
materials for whether the session has already happened.
