# Troubleshooting — Hybrid Update Management

## Azure Update Manager Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Machine not visible in AUM | Wrong subscription filter or Arc agent not connected | Check tenant/subscription; verify Arc agent status |
| Assessment shows stale data | Periodic assessment not enabled | Enable periodic assessment via policy or manually |
| Maintenance window ran but no updates installed | Classifications don't match available updates | Review classification filters in maintenance config |
| Update failed on specific machine | Various — OS error, disk space, reboot pending | Check update history details for error code |

## Arc Agent Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Status "Disconnected" | Agent can't reach Azure | Check outbound connectivity (443/TCP to `*.his.arc.azure.com`) |
| Heartbeat stale | Agent crashed or stopped | Restart `himds` service; check `azcmagent show` |
| Agent won't upgrade | Auto-upgrade disabled or blocked | Enable auto-upgrade; check proxy settings |
| Extensions fail to install | Agent version too old | Upgrade agent manually first |

## Azure Local Update Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Readiness check fails | Unhealthy node, storage, or quorum | Fix the underlying health issue first |
| Update stuck at download | Connectivity from cluster nodes to Azure | Check outbound internet and proxy |
| Node fails to rejoin cluster | Network, storage, or driver issue post-update | Check cluster events; validate network connectivity |
| SBE not available | OEM hasn't released the package | Wait for OEM release — do not force |
| WSUS GPO overriding AUM | GPO conflict | Remove WSUS GPO from cluster nodes — WSUS is unsupported on Azure Local |

## Hotpatching Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Enrollment fails | Missing prerequisites | Verify VBS, Secure Boot, UEFI, Windows Server 2025 |
| Hotpatch not applied | Baseline month or enrollment not active | Check calendar; verify enrollment date |
| Unexpected reboot after hotpatch | Cumulative update also applied | Review update history for non-hotpatch KBs |

## Compliance / Reporting Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Resource Graph returns empty | Wrong subscription scope | Verify query targets correct subscriptions |
| Policy compliance not populated | Evaluation hasn't run yet (can take 24h) | Wait or trigger evaluation manually |
| Cost Management inaccessible | Insufficient RBAC | Requires Cost Management Reader role |

## Useful Commands

```powershell
# Arc agent diagnostics
azcmagent show
azcmagent check

# Check Windows Update service
Get-Service -Name wuauserv | Format-Table Name, Status

# Check pending updates (PowerShell)
$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$results = $searcher.Search("IsInstalled=0")
$results.Updates | Select-Object Title, MsrcSeverity

# Check Azure Local cluster health
Get-ClusterNode | Format-Table Name, State
Get-StorageSubSystem *Cluster* | Get-StorageHealthReport
```
