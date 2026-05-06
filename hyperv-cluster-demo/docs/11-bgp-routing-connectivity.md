# 11 — BGP Routing and Connectivity

## Overview

This document explains the BGP topology that makes the nested lab environment reachable from on-premises and from the Azure Local cluster — without any new VNet peering, UDR, or additional routing configuration.

---

## BGP Topology

```
ON-PREMISES SITE
  ┌─────────────────────────────────────────────┐
  │  FortiGate-90G                              │
  │  ASN: 65421                                 │
  │  BGP Peer: Azure VPN GW                     │
  │  Advertises to Azure: 192.168.211.0/24      │
  │  Receives from Azure: 10.250.0.0/16         │
  │                                             │
  │  Azure Local Cluster: 192.168.211.x         │
  └───────────────────┬─────────────────────────┘
                      │  IPsec VPN tunnel
                      │  BGP over VPN
                      │
               ┌──────┴──────────────────────────────┐
               │  Azure VPN Gateway                  │
               │  ASN: 65422                         │
               │  BGP Peer: FortiGate-90G            │
               │  Advertises to on-prem: 10.250.0.0/16│
               │  Receives from on-prem: 192.168.211.0/24│
               └──────┬──────────────────────────────┘
                      │
               ┌──────┴───────────────────────────────────────┐
               │  VNet: vnet-lab-prodtech-eus-connectivity-hub │
               │  10.250.0.0/16                               │
               │                                              │
               │  Subnet: snet-lab-prodtech-eus-connectivity-mgmt│
               │  10.250.2.0/24                               │
               │                                              │
               │  172.16.10.10  dc01.azrl.mgmt                 │
               │  172.16.10.11  dc02.azrl.mgmt                 │
               │  10.250.2.5  hv-host01   (host VM)          │
               │  10.250.2.6  → hvwac01   (secondary IP)     │
               │  10.250.2.7  → hvscvmm01 (secondary IP)     │
               └──────────────────────────────────────────────┘
```

---

## BGP Route Advertisement Explained

### What the FortiGate Advertises to Azure

```
BGP UPDATE from FortiGate (ASN 65421):
  NLRI: 192.168.211.0/24  ← Azure Local cluster network
  Next-hop: FortiGate WAN IP
```

This means Azure VMs know that to reach `192.168.211.x` they should route via the VPN tunnel to the FortiGate.

### What Azure VPN GW Advertises to On-Premises

```
BGP UPDATE from Azure VPN GW (ASN 65422):
  NLRI: 10.250.0.0/16  ← entire Azure VNet address space
  Next-hop: VPN GW tunnel IP
```

This means the FortiGate's routing table has an entry:
```
10.250.0.0/16  via  [VPN tunnel to Azure]
```

And since FortiGate propagates BGP routes to the on-premises network, **all on-premises clients automatically know how to reach any IP in 10.250.0.0/16**, including:
- `10.250.2.5` (the host VM)
- `10.250.2.6` (hvwac01 via secondary IP)
- `10.250.2.7` (hvscvmm01 via secondary IP)

---

## How Secondary IP Forwarding Works

### The Problem

Azure routes traffic destined for `10.250.2.6` to the NIC that owns that IP — `nic-hv-host01`. The traffic arrives at the host OS. But the actual service (WAC vMode) is running on `hvwac01` at `172.16.10.30` — a private address inside the nested environment that is not reachable from outside the host.

### The Solution: IP Forwarding + Static Routes

1. **Azure NIC IP forwarding** is enabled: Azure delivers packets destined for secondary IPs to the host OS without dropping them
2. **Host OS IP routing** is enabled (`IPEnableRouter = 1`)
3. **Static routes** tell the host OS where to send traffic for `.46` and `.47`
4. **Nested VMs** are configured with the secondary IP on their External vSwitch NIC

```
Traffic flow for 10.250.2.6 (hvwac01):

On-prem client → FortiGate → IPsec tunnel → Azure VPN GW
→ Azure routes to NIC nic-hv-host01 (which owns .46)
→ Azure NIC IP forwarding: forwards to host OS
→ Host OS routing table: 172.16.10.30 via 172.16.10.1 (host vNIC)
→ vSwitch-Mgmt → hvwac01 (172.16.10.30)
→ hvwac01 responds from 10.250.2.6 (its External vSwitch NIC)
→ Reply: hvwac01 → vSwitch-External → Azure NIC → VPN tunnel → FortiGate → on-prem client
```

### Why No UDR Is Needed

A User Defined Route (UDR) would only be needed if traffic needed to be redirected **between subnets or to a different resource** within Azure. In this case, the traffic is destined for a specific NIC IP that is already on the host VM's NIC — Azure's built-in NIC-level IP forwarding handles it. No subnet-level route override is required.

---

## Azure Local Cluster Connectivity Path

The Azure Local cluster at `192.168.211.x` can reach the nested VMs as follows:

| Azure Local Source | Destination | Route | Protocol |
|-------------------|-------------|-------|----------|
| Any node (192.168.211.x) | `hv-host01` (10.250.2.5) | FortiGate → VPN → VNet | Any |
| Any node | `hvwac01` (10.250.2.6) | FortiGate → VPN → NIC forwarding → nested VM | HTTPS/443 |
| Any node | `hvscvmm01` (10.250.2.7) | FortiGate → VPN → NIC forwarding → nested VM | TCP/8100 |
| Any node | `hvnode01-04` (172.16.10.x) | **Not directly routable** | N/A |

The cluster nodes (`hvnode01-04`) are on the private `172.16.10.0/24` network and are **not** advertised via BGP. They are managed through `hvwac01` and `hvscvmm01`, which are reachable.

### Demo Implication

During the demo, show the Azure Local admin connecting to WAC vMode (`https://10.250.2.6`) and managing the nested Hyper-V cluster from their on-premises management station. This demonstrates the BGP connectivity working transparently.

---

## Verifying BGP Route Propagation

### From On-Premises (FortiGate CLI)

```bash
# Show BGP neighbors
get router info bgp neighbors

# Show routes received from Azure
get router info bgp neighbors <azure-vng-tunnel-ip> received-routes | grep "10.250"

# Confirm 10.250.0.0/16 in routing table
get router info routing-table all | grep "10.250.0.0"
```

### From Azure (Effective Routes)

```powershell
# Check effective routes on the host VM's NIC
az network nic show-effective-route-table `
  --name "nic-hv-host01" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --query "value[?contains(addressPrefix[0], '192.168')]" `
  --output table

# Should show 192.168.211.0/24 via VirtualNetworkGateway
```

### From Azure Local Cluster (Windows)

```powershell
# From an Azure Local cluster node
route print | Select-String "10.250"
# Should show: 10.250.0.0  255.255.0.0  <VPN tunnel gateway>

# Test connectivity
Test-Connection -ComputerName "10.250.2.5" -Count 4
Test-Connection -ComputerName "10.250.2.6" -Count 4
Test-Connection -ComputerName "10.250.2.7" -Count 4

# Test WAC vMode HTTPS
Invoke-WebRequest -Uri "https://10.250.2.6" -UseBasicParsing `
    -SkipCertificateCheck -TimeoutSec 10
```

---

## What Happens Without BGP (Why You Cannot Use a New VNet)

If a new VNet were created instead of using the existing one, the following would break:

1. **No BGP advertisement**: A new VNet would need explicit peering with the hub VNet that has the VPN Gateway. VNet peering does propagate routes, but only if the peering is configured with **Use Remote Gateways** (on the spoke side) and **Allow Gateway Transit** (on the hub side).

2. **Route propagation delay**: Even with proper peering settings, adding a new VNet requires re-evaluating the BGP route table and coordinating with the network team.

3. **Existing DNS infrastructure unchanged**: Placing the host in the existing subnet means the existing DCs at `.36` and `.37` are immediately reachable for DNS and Kerberos without any DNS forwarder configuration.

4. **Operational simplicity**: Zero additional Azure networking resources means zero additional things to break on demo day.

---

## Network Troubleshooting Reference

### Symptom: On-prem can't reach 10.250.2.6

```powershell
# Step 1: Confirm secondary IP is assigned to the NIC
az network nic show --name "nic-hv-host01" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --query "ipConfigurations[].privateIPAddress"

# Step 2: Confirm IP forwarding is enabled on the NIC
az network nic show --name "nic-hv-host01" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --query "enableIPForwarding"

# Step 3: Confirm host OS routing is enabled
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" |
    Select-Object IPEnableRouter

# Step 4: Confirm hvwac01 has 10.250.2.6 on its External NIC
Invoke-Command -ComputerName "172.16.10.30" -ScriptBlock {
    Get-NetIPAddress | Where-Object IPAddress -eq "10.250.2.6"
}
```

### Symptom: BGP route for 10.250.0.0/16 missing on FortiGate

Contact the network team to verify:
- VPN tunnel to Azure VPN GW is up
- BGP session between FortiGate (65421) and Azure VPN GW (65422) is established
- Azure VPN GW is configured to advertise the VNet address space via BGP (`--enable-bgp true`)
