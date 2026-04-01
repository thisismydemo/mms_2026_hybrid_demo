# Hotpatching

## What It Is

Hotpatching applies security updates **in memory** without requiring a reboot. Instead of 12 monthly reboots, servers reboot only during **baseline months** (January, April, July, October) — the other 8 months are hotpatch-only.

## Calendar Pattern

| Month | Type | Reboot? |
|-------|------|---------|
| January | Baseline | Yes |
| February | Hotpatch | No |
| March | Hotpatch | No |
| April | Baseline | Yes |
| May | Hotpatch | No |
| June | Hotpatch | No |
| July | Baseline | Yes |
| August | Hotpatch | No |
| September | Hotpatch | No |
| October | Baseline | Yes |
| November | Hotpatch | No |
| December | Hotpatch | No |

**Result: 8 months of no-reboot security patching.**

## Where It Works

| Platform | Supported | Cost |
|----------|----------|------|
| Azure VMs (Windows Server 2022 Azure Edition) | Yes | Free |
| Azure VMs (Windows Server 2025) | Yes | Free |
| Azure Local guest VMs (Windows Server 2025) | Yes | Free |
| Arc-enabled on-prem (Windows Server 2025) | Yes | ~$1.50/core/month |
| Windows Server 2022 Standard/Datacenter (non-Azure) | No | — |
| Windows Server 2019 or earlier | No | — |

## Prerequisites

- **Windows Server 2025** (Standard or Datacenter)
- **Azure Arc agent** installed and connected (for on-prem)
- **VBS** (Virtualization-Based Security) enabled
- **Secure Boot** enabled
- **UEFI** boot mode

## Enrollment

1. Navigate to the Arc-enabled server in the Azure portal
2. Go to **Updates → Hotpatch**
3. Enable hotpatch enrollment
4. Billing starts immediately ($1.50/core/month for Arc servers)

## Verification

- Check **Update history** for the machine
- Hotpatch months: updates install with no reboot event
- Baseline months: updates require a reboot
- In **Azure Update Manager → Machines**: add the **Hotpatch status** column to see fleet-wide enrollment
