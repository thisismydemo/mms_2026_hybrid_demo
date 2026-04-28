# Demo Standards — MMS MOA 2026

> **Demo:** The Hybrid Update Blues
> **Conference:** MMS MOA 2026
> **Owner:** Kristopher Turner
> **Tenant:** `a9b67171-3fbb-45bf-8394-eb56d02a86e4`

These standards apply to every resource, script, and document created for this demo. Any resource deployed in this tenant that belongs to this demo must conform to these conventions so it is immediately identifiable, auditable, and cleanable.

---

## Table of Contents

1. [Naming Conventions](#naming-conventions)
2. [Tagging Standards](#tagging-standards)
3. [PowerShell Script Standards](#powershell-script-standards)
4. [Bicep / IaC Standards](#bicep--iac-standards)
5. [Document Standards](#document-standards)
6. [Quick Reference Cheat Sheet](#quick-reference-cheat-sheet)

---

## Naming Conventions

### Pattern

```
{prefix}-{demoCode}-{conferenceCode}-{environment}-{region}-{sequence}
```

| Token            | Definition                                      | Value for this demo |
|------------------|-------------------------------------------------|---------------------|
| `prefix`         | Azure resource type abbreviation (see table)    | varies              |
| `demoCode`       | Short identifier for the demo                   | `hyb`               |
| `conferenceCode` | Conference short code                           | `mms26`             |
| `environment`    | Lifecycle stage                                 | `demo`              |
| `region`         | Azure region short code                         | `eus` (eastus)      |
| `sequence`       | Two-digit zero-padded number                    | `01`, `02`, …       |

> **Storage accounts** omit dashes and drop `environment` to stay within the 24-character limit:
> `st{demoCode}{conferenceCode}{region}{sequence}` → `sthybmms26eus01`

### Resource Type Prefixes

| Resource Type                        | Prefix    | Example                             |
|--------------------------------------|-----------|-------------------------------------|
| Resource Group                       | `rg-`     | `rg-hyb-mms26-demo-eus-01`          |
| Virtual Machine                      | `vm-`     | `vm-hyb-mms26-demo-eus-01`          |
| Virtual Network                      | `vnet-`   | `vnet-hyb-mms26-demo-eus-01`        |
| Subnet                               | `snet-`   | `snet-hyb-mms26-demo-eus-01`        |
| Network Security Group               | `nsg-`    | `nsg-hyb-mms26-demo-eus-01`         |
| Key Vault                            | `kv-`     | `kv-hyb-mms26-demo-eus-01`          |
| Storage Account                      | `st`      | `sthybmms26eus01`                   |
| Log Analytics Workspace              | `log-`    | `log-hyb-mms26-demo-eus-01`         |
| Managed Identity                     | `mi-`     | `mi-hyb-mms26-demo-eus-01`          |
| Recovery Services Vault              | `rsv-`    | `rsv-hyb-mms26-demo-eus-01`         |
| Automation Account                   | `aa-`     | `aa-hyb-mms26-demo-eus-01`          |
| Maintenance Configuration            | `mc-`     | `mc-hyb-mms26-demo-eus-01`          |
| Arc-enabled Machine                  | inherits physical machine name — prefix not overridden |   |
| Data Collection Rule                 | `dcr-`    | `dcr-hyb-mms26-demo-eus-01`         |
| Action Group                         | `actgrp-` | `actgrp-hyb-mms26-demo-eus-01`      |
| Policy Assignment                    | `pa-`     | `pa-hyb-mms26-demo-eus-01`          |
| Policy Initiative                    | `pi-`     | `pi-hyb-mms26-demo-eus-01`          |

### Naming Rules

- **All lowercase** — no uppercase anywhere.
- **Hyphens only** as separators (no underscores, no dots), except storage accounts (no separators).
- **No abbreviation invented on the fly** — use the table above. If a type is missing, add it to this table first, then use it.
- **Sequence numbers** only when multiple instances of the same type exist in the same scope. Use `01` for first; never bare `1`.
- **Region** uses short codes: `eus` (East US), `wus2` (West US 2), `cus` (Central US).
- **Arc-enabled machine names** inherit the physical name registered during onboarding — they may not follow the pattern, and that is acceptable.

---

## Tagging Standards

Every Azure resource created for this demo **must** have all required tags. No exceptions.

### Required Tags

| Tag Key       | Description                              | Value for this demo                                              |
|---------------|------------------------------------------|------------------------------------------------------------------|
| `Demo`        | Human-readable demo name                 | `The Hybrid Update Blues`                                        |
| `Conference`  | Conference this demo was built for       | `MMSMOA 2026`                                                    |
| `Owner`       | Person responsible for the resources     | `Kristopher Turner`                                              |
| `Environment` | Lifecycle stage                          | `Demo`                                                           |
| `CostCenter`  | Cost tracking code                       | `MMSMOA2026`                                                     |
| `ManagedBy`   | How this was provisioned                 | `GitHub Copilot`                                                 |
| `Repository`  | Source repo URL                          | `https://github.com/thisismydemo/mms_2026_hybrid_demo`           |

### Applying Tags in PowerShell

The `$Global:DemoTags` hashtable is available after loading the demo environment:

```powershell
. .\scripts\00-load-demo-env.ps1

# Azure PowerShell
New-AzResourceGroup -Name $rg -Location $loc -Tag $Global:DemoTags

# Existing resource
Update-AzTag -ResourceId $resourceId -Tag $Global:DemoTags -Operation Merge

# Azure CLI (convert hashtable to space-separated key=value pairs)
$tagArgs = $Global:DemoTags.GetEnumerator() | ForEach-Object { "$($_.Key)='$($_.Value)'" }
az resource tag --ids $resourceId --tags @tagArgs

# Maintenance configurations (az CLI)
az maintenance configuration update `
    --resource-group $rg --resource-name $mcName `
    --tags @tagArgs
```

### Applying Tags via Azure Policy

The repo's `policy/` folder includes tag-enforcement policy assignments. The policy assignment `pa-hyb-mms26-demo-eus-01` enforces required tags on all resources in the demo resource group and triggers a remediation task for non-compliant existing resources.

---

## PowerShell Script Standards

### File Naming

```
##-kebab-case-description.ps1
```

- Two-digit prefix defines execution order (`00`, `01`, … `09`, `10`, …).
- All lowercase kebab-case after the prefix.
- `00-load-demo-env.ps1` is always the environment loader — dot-source it first.

### Required Header Block

Every script must begin with:

```powershell
#Requires -Version 7.2
<#
.SYNOPSIS
    One-line summary of what the script does.

.DESCRIPTION
    Longer description. Include what Azure resources it creates/modifies
    and any side effects.

.PARAMETER ParameterName
    Description of the parameter.

.EXAMPLE
    .\##-script-name.ps1 -ParameterName value

    Explain what this example does.

.NOTES
    Demo    : The Hybrid Update Blues
    Session : MMS MOA 2026
    Owner   : Kristopher Turner
    Repo    : https://github.com/thisismydemo/mms_2026_hybrid_demo
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string] $SubscriptionId,
    ...
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
```

### Standard Helper Functions

Include these in every script (or dot-source them from a shared helpers file):

```powershell
#region Helpers
function Write-Step    { param([string]$M) Write-Host "`n==> $M" -ForegroundColor Cyan }
function Write-Success { param([string]$M) Write-Host "    [OK]   $M" -ForegroundColor Green }
function Write-Warn    { param([string]$M) Write-Host "    [WARN] $M" -ForegroundColor Yellow }
function Write-Fail    { param([string]$M) Write-Host "    [FAIL] $M" -ForegroundColor Red; throw $M }
#endregion
```

### Structure Rules

- Use `#region Name` / `#endregion` to group logical sections.
- Standard sections in order: **Helpers → Prerequisites → Auth → Main Logic → Summary**.
- Never hard-code subscription IDs, resource group names, or credentials — always pull from `$Global:DemoEnv`.
- Never prompt for passwords mid-script — use `SecureString` parameters or read from Key Vault.
- Always check `$LASTEXITCODE` after `az` CLI calls.
- Apply `$Global:DemoTags` to every resource created.
- Clean up with `06-cleanup-demo.ps1` that honours `-WhatIf`.

### Error Handling Pattern

```powershell
try {
    Write-Step "Creating maintenance configuration $mcName"
    # ... work ...
    Write-Success "Maintenance configuration created"
} catch {
    Write-Fail "Failed to create maintenance configuration: $_"
}
```

---

## Bicep / IaC Standards

### File Organization

```
bicep/                             (if IaC is added to this repo)
  main.bicep
  modules/
    {resource-type}.bicep
  parameters/
    demo.bicepparam
```

### Required File Header

```bicep
// =============================================================================
// {filename}
// MMS MOA 2026 – The Hybrid Update Blues
// {One-line description}
// =============================================================================
```

### Required Parameters

Every Bicep file must declare:

```bicep
@description('Azure region.')
param location string = resourceGroup().location

@description('Resource tags. See STANDARDS.md tagging section.')
param tags object = {}
```

---

## Document Standards

### Required Front Matter (top of every `.md` file)

```markdown
# {Title}

> **Demo:** The Hybrid Update Blues
> **Conference:** MMS MOA 2026
> **Author:** Kristopher Turner
> **Last Updated:** YYYY-MM-DD
```

### Standard Sections

| Document Type              | Required Sections                                                                                |
|----------------------------|--------------------------------------------------------------------------------------------------|
| Demo setup guide (`docs/`) | Overview · Prerequisites · Step-by-step instructions · Validation · Troubleshooting              |
| Policy guide (`policy/`)   | Purpose · Policy definitions · Assignment plan · Remediation notes · Compliance queries          |
| Presenter guide            | Session goals · Pre-demo checklist · Step-by-step talking points · Expected outcomes · Fallbacks |
| README                     | Description · Quick start · Prerequisites · Structure · Contributing                             |
| Query file (`queries/`)    | Header comment explaining purpose · KQL or CLI snippet · Expected output description             |

### Formatting Rules

- One H1 (`#`) per document — the document title.
- Use H2 (`##`) for major sections, H3 (`###`) for subsections.
- All code blocks must declare a language: ` ```powershell `, ` ```json `, ` ```bash `, ` ```kql `.
- File paths use forward slashes in documentation.
- Never commit placeholder `TODO` text to `main` — either fill it in or file a GitHub Issue.

---

## Quick Reference Cheat Sheet

### This Demo at a Glance

| Field            | Value                                                         |
|------------------|---------------------------------------------------------------|
| Demo code        | `hyb`                                                         |
| Conference code  | `mms26`                                                       |
| Environment      | `demo`                                                        |
| Primary region   | `eus` (East US)                                               |
| Subscription     | `tpdemos-cmp-lz-azl-legacy-001`                               |
| Owner tag        | `Kristopher Turner`                                           |
| Conference tag   | `MMSMOA 2026`                                                 |
| Demo name tag    | `The Hybrid Update Blues`                                     |
| Repo             | `https://github.com/thisismydemo/mms_2026_hybrid_demo`        |

### Common Resource Names for this Demo

| Resource                  | Name                              |
|---------------------------|-----------------------------------|
| Resource Group            | `rg-hyb-mms26-demo-eus-01`        |
| Log Analytics Workspace   | `log-hyb-mms26-demo-eus-01`       |
| Maintenance Config Ring 1 | `mc-hyb-mms26-demo-eus-01`        |
| Maintenance Config Ring 2 | `mc-hyb-mms26-demo-eus-02`        |
| Maintenance Config Defndr | `mc-hyb-mms26-demo-eus-defender`  |
| Managed Identity          | `mi-hyb-mms26-demo-eus-01`        |
| Data Collection Rule      | `dcr-hyb-mms26-demo-eus-01`       |
| Action Group              | `actgrp-hyb-mms26-demo-eus-01`    |

### Required Tags (copy-paste ready)

```powershell
$tags = @{
    Demo        = 'The Hybrid Update Blues'
    Conference  = 'MMSMOA 2026'
    Owner       = 'Kristopher Turner'
    Environment = 'Demo'
    CostCenter  = 'MMSMOA2026'
    ManagedBy   = 'GitHub Copilot'
    Repository  = 'https://github.com/thisismydemo/mms_2026_hybrid_demo'
}
```

```json
"tags": {
    "Demo": "The Hybrid Update Blues",
    "Conference": "MMSMOA 2026",
    "Owner": "Kristopher Turner",
    "Environment": "Demo",
    "CostCenter": "MMSMOA2026",
    "ManagedBy": "GitHub Copilot",
    "Repository": "https://github.com/thisismydemo/mms_2026_hybrid_demo"
}
```
