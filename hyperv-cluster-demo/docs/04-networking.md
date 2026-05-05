# 04 — Networking

## Overview

The networking design uses **one Azure NIC** with multiple IP configurations to expose two nested VMs on routable Azure IP addresses, while keeping the remaining nested VMs on isolated private networks accessible only through the host. Outbound internet for nested VMs is provided by WinNAT on the host OS.

---

## Why the Existing Subnet Is Used

**No new VNet or subnet is created.** The host VM is placed directly in:

- **VNet**: `vnet-lab-prodtech-eus-connectivity-hub` (`10.250.0.0/16`)
- **Subnet**: `snet-lab-prodtech-eus-connectivity-mgmt` (`10.250.1.0/24`)

The reason is BGP. The FortiGate-90G (ASN 65421) at the on-premises site peers with the Azure VPN Gateway (ASN 65422) and advertises `10.250.0.0/16` bidirectionally. Any IP address in that range is automatically reachable from:

- The Azure Local cluster (`192.168.211.x`)
- Corporate network clients
- Other on-premises servers

This means that by assigning `10.250.1.46` and `10.250.1.47` as secondary IPs on the host's Azure NIC and enabling IP forwarding, the nested VMs `hvwac01` and `hvscvmm01` become directly reachable from on-premises **with no additional routing configuration**. See [`docs/11-bgp-routing-connectivity.md`](11-bgp-routing-connectivity.md) for the full BGP topology.

---

## Azure NIC Configuration

The host VM's NIC (`nic-hv-host01`) has three IP configurations:

| IP Config Name | IP Address | Purpose |
|----------------|-----------|---------|
| `ipconfig-primary` | `10.250.1.45` (static) | Host VM management, RDP, deployment |
| `ipconfig-wac` | `10.250.1.46` (static) | Secondary IP → forwarded to `hvwac01` |
| `ipconfig-scvmm` | `10.250.1.47` (static) | Secondary IP → forwarded to `hvscvmm01` |

**IP forwarding** must be enabled on the NIC at the Azure platform level:

```powershell
az network nic update `
  --name "nic-hv-host01" `
  --resource-group "rg-hvlab-mms26-eus-01" `
  --ip-forwarding true
```

---

## vSwitch Layout

### vSwitch-External

```
Type:    External (bound to Azure NIC)
Purpose: Connects nested VMs to the Azure network
         hvwac01 and hvscvmm01 each have a vNIC on this switch
         with static IPs 10.250.1.46 and 10.250.1.47 respectively
Notes:   The host OS also uses the Azure NIC — Hyper-V shares the
         physical NIC between the host management OS and the external switch
```

### vSwitch-Mgmt

```
Type:    Internal
Network: 172.16.10.0/24
Gateway: 172.16.10.1 (host OS virtual NIC)
Purpose: Management traffic — RDP, PS Remoting, domain join,
         WMI, Hyper-V remote management
VMs:     All nested VMs have a NIC on this switch
DNS:     172.16.10.10 (hvdc01) primary, 10.250.1.36 secondary
```

### vSwitch-Migration

```
Type:    Private (no host OS adapter)
Network: 172.16.20.0/24
Purpose: Live migration traffic only
VMs:     hvnode01-04 only
Notes:   Private switch prevents host OS from interfering with
         migration bandwidth
```

### vSwitch-Storage

```
Type:    Private
Network: 172.16.30.0/24
Purpose: iSCSI target/initiator traffic, MPIO paths
VMs:     hviscsi01 (two NICs: .10 and .11) + hvnode01-04 (two NICs each)
Notes:   Dual NICs on each VM enable MPIO over two independent paths
         Never route management traffic on this switch
```

### vSwitch-Heartbeat

```
Type:    Private
Network: 172.16.40.0/24
Purpose: Failover Cluster heartbeat (cluster network priority: highest)
VMs:     hvnode01-04 only
Notes:   Dedicated switch ensures heartbeat is never competing with
         storage or migration traffic
```

### vSwitch-Workload

```
Type:    Internal
Network: 172.16.50.0/24
Purpose: Network for guest VMs created during demo scenarios
VMs:     hvnode01-04 (one NIC each on workload switch)
Notes:   Internal type allows host to reach workload VMs for demo purposes
```

---

## NIC Layout Per Nested VM

| VM | vSwitch-External | vSwitch-Mgmt | vSwitch-Migration | vSwitch-Storage (×2) | vSwitch-Heartbeat | vSwitch-Workload |
|----|:---:|:---:|:---:|:---:|:---:|:---:|
| `hvdc01` | — | ✓ | — | — | — | — |
| `hviscsi01` | — | ✓ | — | ✓✓ | — | — |
| `hvnode01-04` | — | ✓ | ✓ | ✓✓ | ✓ | ✓ |
| `hvwac01` | ✓ | ✓ | — | — | — | — |
| `hvscvmm01` | ✓ | ✓ | — | — | — | — |

---

## Host OS vNICs

The host OS (Hyper-V management OS) has a virtual NIC on each Internal vSwitch:

| Host vNIC | IP | Gateway | Purpose |
|-----------|-----|---------|---------|
| `vEthernet (vSwitch-Mgmt)` | `172.16.10.1/24` | — | Gateway for nested VMs' outbound traffic via WinNAT |
| `vEthernet (vSwitch-Workload)` | `172.16.50.1/24` | — | Access to workload guest VMs from host OS |

The host OS does **not** have a vNIC on Private switches (Storage, Migration, Heartbeat) — those are exclusive to the nested VMs.

---

## WinNAT for Nested VM Outbound Access

Nested VMs on `vSwitch-Mgmt` (172.16.10.0/24) need outbound access to:
- Azure Key Vault (to retrieve secrets during setup)
- Windows Update servers
- GitHub (for Actions runner registration)
- Azure Blob storage (for ISO downloads, Cloud Witness)

WinNAT on the host provides this without exposing the private 172.16.x.x ranges externally:

```powershell
# On the host VM — configure WinNAT for the Mgmt network
New-NetNat `
  -Name "NatMgmt" `
  -InternalIPInterfaceAddressPrefix "172.16.10.0/24"

# Set the host vNIC as the gateway for nested VMs
# (nested VMs use 172.16.10.1 as their default gateway)
New-NetIPAddress `
  -IPAddress "172.16.10.1" `
  -PrefixLength 24 `
  -InterfaceAlias "vEthernet (vSwitch-Mgmt)"
```

> WinNAT supports up to ~16,000 concurrent NAT translations. This is more than sufficient for the demo environment.

---

## Secondary IP Forwarding (10.250.1.46 → hvwac01 / 10.250.1.47 → hvscvmm01)

When traffic destined for `10.250.1.46` arrives at the host VM's NIC, the Azure platform delivers it to the host OS because `.46` is a registered secondary IP on the NIC. The host OS then needs to forward it to the appropriate nested VM.

### Configuration Steps

1. **Azure NIC IP forwarding** (already covered above — `az network nic update --ip-forwarding true`)

2. **Host OS routing** — add routes so the host OS knows to forward `.46` and `.47` to the nested VMs:

```powershell
# Enable IP routing in the host OS
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" `
  -Name "IPEnableRouter" -Value 1

# Add static routes from secondary IPs to nested VM Mgmt IPs
# 10.250.1.46 → hvwac01 at 172.16.10.30
route add 172.16.10.30 mask 255.255.255.255 172.16.10.1 -p

# 10.250.1.47 → hvscvmm01 at 172.16.10.40
route add 172.16.10.40 mask 255.255.255.255 172.16.10.1 -p
```

3. **Nested VM configuration** — `hvwac01` and `hvscvmm01` must be configured to answer on their secondary Azure IPs:

```powershell
# On hvwac01 — bind the Azure secondary IP to the External vSwitch NIC
New-NetIPAddress `
  -IPAddress "10.250.1.46" `
  -PrefixLength 24 `
  -DefaultGateway "10.250.1.1" `
  -InterfaceAlias "Ethernet (vSwitch-External)"

# On hvscvmm01 — bind the Azure secondary IP to the External vSwitch NIC
New-NetIPAddress `
  -IPAddress "10.250.1.47" `
  -PrefixLength 24 `
  -DefaultGateway "10.250.1.1" `
  -InterfaceAlias "Ethernet (vSwitch-External)"
```

---

## DNS Configuration for Nested VMs

All nested VMs use the following DNS configuration:

| DNS Order | Server | Purpose |
|-----------|--------|---------|
| Primary | `172.16.10.10` | `hvdc01` — replica DC inside nested environment |
| Secondary | `10.250.1.36` | Existing production DC (fallback — reachable via BGP/NIC) |

During initial setup (before `hvdc01` is promoted), use `10.250.1.36` and `10.250.1.37` temporarily.

---

## iSCSI Network Isolation

The Storage vSwitch is **intentionally isolated** (Private type) from the host management OS. This ensures:

1. iSCSI traffic never competes with management or migration bandwidth
2. No routing between the iSCSI network and the management network (prevents accidental iSCSI traffic over wrong paths)
3. MPIO operates over dedicated paths between hviscsi01 and cluster nodes

### iSCSI Network Layout

```
vSwitch-Storage (172.16.30.0/24)
  hviscsi01:
    NIC 1: 172.16.30.10  (iSCSI target path A)
    NIC 2: 172.16.30.11  (iSCSI target path B)
  
  hvnode01:
    NIC 1: 172.16.30.21  (initiator path A → target .10)
    NIC 2: 172.16.30.25  (initiator path B → target .11)
  
  hvnode02:
    NIC 1: 172.16.30.22
    NIC 2: 172.16.30.26
  
  hvnode03:
    NIC 1: 172.16.30.23
    NIC 2: 172.16.30.27
  
  hvnode04:
    NIC 1: 172.16.30.24
    NIC 2: 172.16.30.28
```

Each cluster node has two independent MPIO paths to the iSCSI target. See [`docs/06-iscsi-storage.md`](06-iscsi-storage.md) for full MPIO configuration.

---

## Network Security Group

The subnet NSG (`nsg-snet-lab-prodtech-eus-connectivity-mgmt`) should be reviewed to ensure the following inbound rules exist or are not blocked:

| Rule | Protocol | Port | Source | Destination | Purpose |
|------|----------|------|--------|-------------|---------|
| Allow-RDP | TCP | 3389 | Corp IP range | `10.250.1.45` | Admin access to host |
| Allow-WinRM | TCP | 5985, 5986 | `10.250.0.0/16` | `10.250.1.45-.47` | PowerShell remoting |
| Allow-HTTPS | TCP | 443 | `10.250.0.0/16` | `10.250.1.46` | WAC vMode web UI |
| Allow-HTTPS-SCVMM | TCP | 443, 8100 | `10.250.0.0/16` | `10.250.1.47` | SCVMM console |

> Verify with your network team that the FortiGate policy permits these flows from on-premises source IPs.
