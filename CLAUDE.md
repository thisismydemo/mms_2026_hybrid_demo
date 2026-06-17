# mms_2026_hybrid_demo — Claude Code Context

## What this repo is

End-to-end demo repository for the **"The Hybrid Update Blues: Patching Everything from Cloud to Closet"** session at MMS MOA 2026. Covers Azure Update Manager, Azure Arc onboarding, Azure Local update management, hotpatching on Windows Server 2025, and compliance reporting — all from a single pane of glass.

---

## ADO project details

- **ADO org:** https://dev.azure.com/hybridcloudsolutions
- **ADO project:** This Is My Demo
- **Area path:** Platform Engineering\Onboarding
- **Work item format:** `AB#<id>` in commit messages and PR descriptions

---

## Standards

This repo follows all HCS platform standards defined in the Platform Engineering repo:

| Standard | Reference |
|---|---|
| Governance | [docs/standards/governance.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/governance.md) |
| Scripting (PowerShell 7) | [docs/standards/scripting.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/scripting.md) |
| Automation | [docs/standards/automation.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/automation.md) |
| Variables and naming | [docs/standards/variables.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/variables.md) |
| Documentation | [docs/standards/documentation.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/documentation.md) |
| Claude Code | [docs/standards/claude-code.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/claude-code.md) |

Key rules:
- All scripts: PowerShell 7+ only. `#Requires -Version 7.0`, `Set-StrictMode -Version Latest`, ` $ErrorActionPreference = 'Stop'`.
- All docs: Markdown only. No Word documents in any repo.
- Commit format: `type(scope): short description` — types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`
- No secrets, tokens, or credentials committed to any file.

---

## Key facts

| Fact | Value |
|---|---|
| Primary language | Bicep / Terraform (HCL) |
| GitHub org | thisismydemo |
| Azure login | kris@hybridsolutions.cloud |
| Key Vault | kv-hcs-vault-01 |

### Environment variables expected

| Variable | Source | Purpose |
|---|---|---|
| `AZURE_SUBSCRIPTION_ID` | kv-hcs-vault-01 via Load-HCSEnvironment.ps1 | Azure CLI subscription context |
| `AZURE_DEVOPS_EXT_PAT` | kv-hcs-vault-01 via Load-HCSEnvironment.ps1 | ADO CLI (`az boards`, `az devops`) |
Load before starting a session:
```powershell
. D:\git\platform\scripts\Load-HCSEnvironment.ps1
```

### Build and test commands

```
az deployment group create --resource-group <rg> --template-file main.bicep --parameters @params.json
```

---

## Repo structure

```
mms_2026_hybrid_demo/
├── .claude/
    └── settings.json
├── .github/
    └── workflows/
├── assets/
    ├── diagrams/
    ├── recordings/
    ├── screenshots/
    └── README.md
├── docs/
    ├── 01-overview.md
    ├── 02-azure-update-manager.md
    ├── 03-arc-onboarding.md
    ├── 04-azure-local-updates.md
    └── 05-hotpatching.md
├── hyperv-cluster-demo/
    ├── bicep/
    ├── config/
    ├── docs/
    ├── scripts/
    └── README.md
├── policy/
    ├── assignment-plan.md
    ├── built-in-policy-reference.md
    └── remediation-notes.md
├── presenter/
    ├── day-of-checklist.md
    ├── fallback-plan.md
    ├── run-of-show.md
    └── slide-map.md
├── queries/
    ├── log-analytics/
    └── resource-graph/
├── scripts/
    ├── 00-load-demo-env.ps1
    ├── 01-prepare-demo-environment.ps1
    ├── 02-create-maintenance-configurations.ps1
    ├── 03-tag-update-rings.ps1
    └── 04-export-update-compliance.ps1
├── .gitignore
├── CLAUDE.md
├── Demo-Guide-Hybrid-Update-Blues.md
├── env.sample.json
├── README.md
└── STANDARDS.md
```

---

## Claude Code actions

**Run autonomously:**
- Read, search, and grep any file in this repo
- Write and edit files in this repo
- `git add`, `git commit`, `git push`
- `gh issue`, `gh pr`, `gh run` CLI commands
- `az` CLI read operations: `az ... show`, `az ... list`
- `bicep build` and Terraform `init` + `plan` (read-only passes only)

**Always confirm before:**
- Creating or deleting Azure resources
- Any `az` CLI write operation that modifies Azure state
- Running destructive operations
- Making API calls to external services
- `az deployment` commands
- `terraform apply`
- Any write to Azure state

---

## Subagents available in this repo

- `mms_2026_hybrid_demo-engineer` (model: sonnet) — Demo engineer for MMS 2026 Hybrid Update Blues session: Bicep templates, demo scripts, presenter materials.

User-level agents (every repo): `triage-lookup`, `markdown-prose-editor`, `azurelocal-domain-expert`, `mkdocs-material-doctor`, `turner-module-scaffold-engineer`, `mms-2026-demo-presenter`.

Platform repo agents (when working in `D:\git\platform`): `orchestration-pm`, `security-waf-caf`, `terraform-validator`, `bicep-validator`, `arm-validator`, `ansible-linter`, `powershell-linter`, `reviewer`, `security-reviewer`, `documenter`, `coder`, `planner`, `operator`, `investigator`, `test-writer`, `router`.

---

## Owner

**Kristopher Turner**
kris@hybridsolutions.cloud
Senior Product Technology Architect, TierPoint | Microsoft MVP (Azure) | MCT
Owner, Hybrid Cloud Solutions LLC — hybridsolutions.cloud
Country Cloud Boy — thisismydemo.cloud

---

## HCS Orchestration Profile

**Validation profile:** iac-bicep — see `D:\git\platform\profiles\iac-bicep.yaml`

This repo is a **pilot** for the `iac-bicep` type in the HCS multi-agent orchestration system.
Run `/dispatch iac-bicep` (or `/dispatch` for all pilots) to validate this repo.

**Repo-specific notes for validators:**
Entry point: hyperv-cluster-demo/bicep/main.bicep. az bicep build and PSRule.Rules.Azure must pass.
