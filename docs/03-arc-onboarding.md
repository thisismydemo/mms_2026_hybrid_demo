# Arc Onboarding

## What Azure Arc Does

Azure Arc projects on-prem servers into Azure Resource Manager as first-class resources. Once Arc-enabled, a server:
- Appears in the Azure portal alongside Azure VMs
- Supports Azure RBAC, tags, and policies
- Can be targeted by Azure Update Manager
- Can have extensions installed (AMA, DSC, etc.)

## Onboarding Methods

| Method | Scale | Use Case |
|--------|-------|----------|
| Single server (portal) | 1 | Quick PoC or lab |
| Scripted (PowerShell / Bash) | 10s | Small environments |
| GPO deployment | 100s–1000s | Domain-joined at scale |
| SCCM task sequence | 100s–1000s | SCCM-managed estates |
| Azure Arc Automanage | Ongoing | Auto-onboard new machines |

## Connected Machine Agent

The agent (`azcmagent`) runs on the server and maintains a heartbeat to Azure.

Key properties:
- **Auto-upgrade**: Enable this. Don't let the agent become another thing to manually patch.
- **Heartbeat**: Reports status every 5 minutes. If last heartbeat > 15 minutes, status shows "Disconnected."
- **Agent version**: Check with `azcmagent version` on the server.

## Agent vs. Azure Monitor Agent (AMA)

| Component | Purpose | Required For |
|-----------|---------|-------------|
| Connected Machine Agent | Projects server into ARM | All Arc scenarios |
| Azure Monitor Agent (AMA) | Sends telemetry to Log Analytics | Monitoring, diagnostics, Insights |

AMA is an extension on top of the Arc agent. You can have Arc without AMA, but not AMA without Arc.

## Post-Onboarding Validation

```powershell
# Check Arc agent status
azcmagent show

# Verify in Azure
az connectedmachine show --name "server-name" --resource-group "rg-name" --query "status"
```

Expected: `"Connected"`

## Update Readiness

Once Arc-enabled, navigate to the server's **Updates** blade in the portal. You should see:
- Assessment results (pending updates by classification)
- Last assessment time
- Ability to trigger on-demand assessment
- Assignment to maintenance configurations
