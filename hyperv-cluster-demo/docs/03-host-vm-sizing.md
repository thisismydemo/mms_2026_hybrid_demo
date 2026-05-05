# 03 — Host VM Sizing

## Chosen SKU: Standard_E104ids_v5

| Property | Value |
|----------|-------|
| SKU | `Standard_E104ids_v5` |
| vCPU | 104 |
| RAM | 672 GB |
| Local NVMe | ~3.8 TB (ephemeral) |
| Temp disk | Included in NVMe |
| Network | Up to 100 Gbps |
| Max NICs | 8 |
| Isolated hardware | **Yes** — dedicated physical host |
| Region | East US |

---

## Why This SKU

### 1. Isolated Hardware

The `v5` series "ids" suffix means **isolated, dedicated storage**. More importantly, the `Standard_E104ids_v5` is an **isolated VM SKU** — the VM runs on a physical host that is not shared with any other customer's workloads. This matters for the demo because:

- **Consistent performance**: No noisy neighbor effects during a live demo with an audience
- **Full vCPU capacity guaranteed**: Intel hyper-threading is stable and predictable
- **Nested virtualization works reliably**: AMD and Intel isolated SKUs both support nested virtualization with consistent performance

### 2. vCPU Count (104 vCPUs)

Hyper-V requires over-commit headroom to handle nested VM startup and migration bursts. The nested load uses 70 vCPUs total, leaving 34 vCPUs for:
- The host OS itself (~4 vCPUs typical under load)
- Hyper-V hypervisor overhead
- Burst headroom during live migration (VMs temporarily run on two nodes during migration)
- GitHub Actions runner workload

### 3. RAM (672 GB)

The nested VMs consume 296 GB of RAM total. The remaining ~376 GB provides:
- Host OS: ~8 GB baseline
- Hyper-V Dynamic Memory overhead: ~20 GB (startup RAM buffers)
- Multiple in-flight live migrations simultaneously
- Workload VMs created during the demo itself
- Safety margin so the host never pages

### 4. Local NVMe (~3.8 TB)

The host VM includes a local NVMe device that is **ephemeral** (lost on deallocate/redeploy). This is intentional for demo use:
- Copy VHDXes from Azure Managed Disks or blob storage to NVMe at start of demo day for dramatically faster I/O
- iSCSI traffic between hviscsi01 and the cluster nodes benefits from NVMe latency rather than Azure disk latency
- **Do not use NVMe for persistent configuration** — store configuration in the VHDX files that live on attached managed disks

---

## Nested VM Load Table

| VM | vCPU | RAM | vSwitch NICs |
|----|------|-----|-------------|
| `hvdc01` | 2 | 8 GB | 1 (Mgmt) |
| `hviscsi01` | 4 | 16 GB | 3 (Mgmt + 2× Storage) |
| `hvnode01` | 16 | 64 GB | 5 (Mgmt + Migration + 2× Storage + Heartbeat) |
| `hvnode02` | 16 | 64 GB | 5 |
| `hvnode03` | 16 | 64 GB | 5 |
| `hvnode04` | 16 | 64 GB | 5 |
| `hvwac01` | 4 | 16 GB | 2 (Mgmt + External) |
| `hvscvmm01` | 8 | 32 GB | 2 (Mgmt + External) |
| **Total** | **82** | **328 GB** | — |

> Note: hvnode vCPU counts include headroom for nested guest VMs created during the demo. Guest VMs do NOT count against the 82 listed here.

---

## vCPU Headroom Math

```
Host physical vCPUs:              104
Nested VM allocation:              82
Host OS + hypervisor overhead:     ~6
Available headroom:                16 vCPUs

Live migration overhead (peak):    ~8 vCPUs (two nodes simultaneously migrating)
Remaining after migration burst:    8 vCPUs

Demo guest VMs (workload):          8 vCPUs (4× 2-vCPU VMs typical)
Net headroom post-demo:             0 vCPUs — plan carefully
```

> **Important**: Do not create more than 4 demo workload VMs (each ≤2 vCPU) during the demo session, or you risk vCPU contention. The DEMO-READY checkpoint should reflect a safe pre-created VM set.

---

## RAM Headroom Math

```
Host physical RAM:                672 GB
Nested VM static allocation:      328 GB
Host OS baseline:                  ~8 GB
Hyper-V startup overhead:         ~20 GB
Total allocated:                  356 GB

Available headroom:               316 GB

Dynamic Memory buffers (10%):     ~33 GB
Live migration working set:       ~64 GB (one full node RAM in-flight)
Demo workload VMs:                ~32 GB (4× 8 GB VMs)
Net RAM headroom post-demo:       187 GB  ← comfortable margin
```

---

## NVMe Performance Tip for Demo Day

The ephemeral NVMe provides significantly lower latency than Azure managed disks for VHDX I/O:

| Storage | Typical 4K Random Read IOPS | Latency |
|---------|----------------------------|---------|
| Azure Premium SSD P30 | ~5,000 IOPS | ~1–2 ms |
| Azure Ultra Disk | ~160,000 IOPS | <1 ms |
| Local NVMe (E104ids_v5) | ~400,000+ IOPS | ~0.1 ms |

### How to Use NVMe on Demo Day

```powershell
# On the host VM — copy VHDXes from managed disk to NVMe before demo
$nvmePath = "D:\HyperV"   # NVMe device typically appears as D:\ on this SKU
$managedDiskPath = "C:\HyperV"

# Create directory structure on NVMe
New-Item -ItemType Directory -Path "$nvmePath\VMs" -Force
New-Item -ItemType Directory -Path "$nvmePath\VHDs" -Force

# Move nested VM storage to NVMe (do this 30 min before demo)
$vms = Get-VM
foreach ($vm in $vms) {
    Move-VMStorage -VMName $vm.Name `
        -DestinationStoragePath "$nvmePath\VMs\$($vm.Name)"
}
```

> **Warning**: NVMe content is lost if the VM is deallocated or the host OS crashes. Always maintain a backup copy on the attached managed disk. Run the DEMO-READY checkpoint creation script while VHDXes are still on managed disks.

---

## Fallback SKUs

If `Standard_E104ids_v5` is unavailable in East US (regional capacity constraints), the following alternatives are viable:

| SKU | vCPU | RAM | Notes |
|-----|------|-----|-------|
| `Standard_E96ids_v5` | 96 | 672 GB | Slightly fewer vCPUs, same RAM. Reduce hvnode vCPU to 14 each. |
| `Standard_E96as_v5` | 96 | 672 GB | AMD EPYC. No isolated hardware. Nested virt works but less consistent. |
| `Standard_M128ms` | 128 | 3,892 GB | Extreme RAM, higher cost. Use only if E-series unavailable. |
| `Standard_D96as_v5` | 96 | 384 GB | Lower RAM — reduce cluster nodes to 2 (hvnode01-02 only). |

### Adjusting for Fallback SKUs

If you must reduce the cluster to 2 nodes with a smaller SKU:

```
hvnode01: 16 vCPU / 64 GB  ← keep
hvnode02: 16 vCPU / 64 GB  ← keep
hvnode03: REMOVE
hvnode04: REMOVE

Cluster: hvlab-clus01 (2-node)
CSVs: reduce to 2 × 300 GB
```

The demo scenarios all work with a 2-node cluster. Live migration still demonstrates correctly between two nodes.

---

## Cost Estimate

| Resource | SKU | Approx. Monthly Cost |
|----------|-----|---------------------|
| Host VM (stopped/deallocated) | Standard_E104ids_v5 | $0 (deallocated) |
| Host VM (running) | Standard_E104ids_v5 | ~$7,200/month |
| Managed Disk (OS) | P10 128 GB | ~$20/month |
| Managed Disk (VHDX storage) | P50 4 TB | ~$280/month |
| Cloud Witness storage | Standard_LRS | <$1/month |

> **Recommendation**: Deallocate the VM when not in active use. At ~$10/hour, leaving it running overnight adds ~$80. Run it only for preparation and the demo day itself. Total estimated lab cost for 2 weeks of prep: ~$400.
