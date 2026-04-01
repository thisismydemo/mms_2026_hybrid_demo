# Policy Assignment Plan

Step-by-step plan for assigning update management policies in the demo environment.

## Phase 1: Audit (Assessment Only)

Assign audit policies first to see the current compliance state without making changes.

| Order | Policy | Effect | Scope |
|---|---|---|---|
| 1 | Machines should be configured to periodically check for missing updates | Audit | Subscription |
| 2 | [Preview]: Configure periodic checking for missing system updates | Audit | Resource Group |

## Phase 2: Enforce (DeployIfNotExists)

After reviewing audit results, escalate to DINE policies to auto-remediate.

| Order | Policy | Effect | Scope |
|---|---|---|---|
| 3 | Configure periodic checking for missing system updates | DeployIfNotExists | Subscription |
| 4 | Schedule recurring updates using Azure Update Manager | DeployIfNotExists | Resource Group |

## Phase 3: Compliance Reporting

- Run a compliance scan: Portal → Policy → Compliance → Trigger evaluation
- Export results to CSV or view in Azure Workbooks
- Cross-reference with Resource Graph queries in `queries/resource-graph/`

## Demo Narrative

1. **Start with Audit** — Show the compliance blade with "X out of Y machines non-compliant"
2. **Assign DINE policy** — Show how Azure auto-configures the periodic assessment
3. **Trigger remediation** — Create a remediation task and show it running
4. **Re-evaluate** — Show compliance improving after remediation completes
