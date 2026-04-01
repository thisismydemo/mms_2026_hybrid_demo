# Cost Model — Hybrid Update Management

## Cost Summary

| Component | Cost | Billing Unit |
|-----------|------|-------------|
| Azure Update Manager — Azure VMs | Free | — |
| Azure Update Manager — Arc-enabled servers | ~$5 | Per server/month |
| Hotpatching — Azure VMs | Free | — |
| Hotpatching — Arc-enabled on-prem | ~$1.50 | Per core/month |
| Azure Resource Graph queries | Free | — |
| Azure Policy (built-in) | Free | — |
| Log Analytics ingestion | ~$2.76 | Per GB |
| Log Analytics Basic Logs | ~$0.65 | Per GB |

## Example: 100-Server Hybrid Estate

| Item | Count | Monthly Cost |
|------|-------|-------------|
| Azure VMs in Update Manager | 40 | $0 |
| Arc-enabled servers in Update Manager | 60 | $300 |
| Hotpatch-enrolled servers (avg 8 cores) | 20 | $240 |
| Log Analytics (10 GB/month) | — | $27.60 |
| **Total** | | **~$567.60/month** |

## Cost Optimization Tips

1. Use **Azure Resource Graph** for compliance reporting before Log Analytics
2. Enable **Basic Logs tier** for high-volume telemetry
3. Set Log Analytics **retention to 30 days** unless compliance requires more
4. Only enable **essential Diagnostic Settings** categories
5. Review **Cost Management** monthly to catch unexpected spikes
6. Consider whether a third-party tool (Nerdio, ControlUp) is cheaper for reporting than raw Log Analytics
