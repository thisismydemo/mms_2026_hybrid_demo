# 09 — WAC Virtualization Mode

> ⭐ **Most important doc in this repository.** Read the entire page before installing.

---

## Critical: WAC Virtualization Mode Is NOT WAC Administration Mode

These are **completely separate products**. Do not confuse them.

| | WAC Administration Mode | WAC Virtualization Mode |
|--|------------------------|------------------------|
| Product focus | Server/OS management | Hyper-V fabric management |
| Architecture | Gateway server, per-session connections | Stateful agents on each managed host |
| Backend database | None (stateless) | PostgreSQL |
| Agents on hosts | No (agentless WinRM/WMI) | Yes — persistent local agent service |
| OS requirement | Windows Server 2019+ | **Windows Server 2025 ONLY** |
| TLS during preview | Standard cert | Self-signed (60-day expiry — see troubleshooting) |
| Can run on same server | With vMode? **NO** | With Admin Mode? **NO** |
| Download URL | https://aka.ms/WACDownload | **https://aka.ms/WACDownloadvMode** |
| Use case | Administer servers, roles | Manage VMs, live migration, storage, fabric |

> **Rule**: `hvwac01` runs **only** WAC Virtualization Mode. If WAC Administration Mode is needed separately, it must be on a different server.

---

## Why WS2025 Is Mandatory for hvwac01

WAC Virtualization Mode is a preview feature that requires the Windows Server 2025 runtime. It will not install on Windows Server 2022. The `hvwac01` VM is deliberately provisioned with the WS2025 evaluation ISO. Do not attempt to change this.

---

## hvwac01 VM Specifications

| Property | Value |
|----------|-------|
| vCPU | 4 |
| RAM | 16 GB |
| OS | **Windows Server 2025** (mandatory) |
| Mgmt NIC IP | `172.16.10.30` (vSwitch-Mgmt) |
| External NIC IP | `10.250.1.46` (vSwitch-External — reachable from on-prem) |
| WAC vMode Web UI | `https://10.250.1.46` (port 443) |
| PostgreSQL | localhost:5432 |
| Domain | `azrl.mgmt` |

---

## Pre-Installation Requirements

### 1. Verify OS Version

```powershell
# On hvwac01 — confirm WS2025
(Get-WmiObject Win32_OperatingSystem).Caption
# Expected: Microsoft Windows Server 2025 Datacenter Evaluation
```

### 2. Install Visual C++ Redistributable

This is a **required prerequisite** — WAC vMode will fail to start without it:

```powershell
# On hvwac01
winget install Microsoft.VCRedist.2015+.x64 --Silent --Accept-Package-Agreements --Accept-Source-Agreements

# Verify installation
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" |
    Select-Object Version, Bld
```

If `winget` is not available:

```powershell
# Alternative: download and install directly
$url = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
Invoke-WebRequest -Uri $url -OutFile "C:\Temp\vc_redist.x64.exe"
Start-Process -FilePath "C:\Temp\vc_redist.x64.exe" -ArgumentList "/install /quiet /norestart" -Wait
```

### 3. Download WAC Virtualization Mode

```powershell
# On hvwac01
$wacVModeUrl = "https://aka.ms/WACDownloadvMode"
$installerPath = "C:\Installers\WACvMode.msi"

New-Item -ItemType Directory -Path "C:\Installers" -Force
Invoke-WebRequest -Uri $wacVModeUrl -OutFile $installerPath -UseBasicParsing

# Confirm download
Get-Item $installerPath | Select-Object Name, Length, LastWriteTime
```

---

## Installation Steps

### Step 1 — Run the Installer

```powershell
# On hvwac01 — install WAC vMode
msiexec /i "C:\Installers\WACvMode.msi" /qn `
    SME_PORT=443 `
    SSL_CERTIFICATE_OPTION=generate `
    /L*v "C:\Installers\WACvMode-install.log"

# Monitor installation log
Get-Content "C:\Installers\WACvMode-install.log" -Wait -Tail 20
```

### Step 2 — Verify PostgreSQL Is Running

WAC vMode installs and manages its own PostgreSQL instance. Verify it started:

```powershell
# Check PostgreSQL service (name varies — look for postgres-related service)
Get-Service | Where-Object { $_.DisplayName -like "*postgres*" -or $_.Name -like "*postgres*" }

# Expected: Running
# If stopped, start it:
Get-Service | Where-Object { $_.Name -like "*postgres*" } | Start-Service
```

### Step 3 — Verify WAC vMode Services

```powershell
# Check all WAC vMode services
Get-Service | Where-Object { $_.DisplayName -like "*Windows Admin Center*" -or
                              $_.DisplayName -like "*WAC*" }

# Services expected to be Running:
# - SmeDesktopService (or similar Windows Admin Center vMode service)
# - PostgreSQL service
```

### Step 4 — Configure Windows Firewall

```powershell
# Allow HTTPS inbound on port 443 for WAC vMode Web UI
New-NetFirewallRule `
    -DisplayName "WAC vMode HTTPS Inbound" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 443 `
    -Action Allow `
    -Profile Any

# Verify
Get-NetFirewallRule -DisplayName "WAC vMode HTTPS Inbound" |
    Select-Object DisplayName, Enabled, Action, Direction
```

### Step 5 — Access the Web UI

From an on-premises or Azure machine:

1. Open a browser and navigate to `https://10.250.1.46`
2. Accept the self-signed TLS certificate warning (expected during preview)
3. Log in with a domain admin account: `AZRL\<your-admin-account>`

> **TLS Certificate Note**: The self-signed certificate expires every **60 days**. See the Troubleshooting section for renewal steps.

---

## Adding Cluster Hosts as Managed Nodes

After logging in to WAC vMode, add the Hyper-V cluster nodes:

### From the WAC vMode UI

1. Click **Add** → **Hyper-V host**
2. Enter the hostname: `hvnode01.azrl.mgmt`
3. Provide credentials: `AZRL\svc-hvlab-wac` with the svc password
4. Repeat for `hvnode02`, `hvnode03`, `hvnode04`
5. Click **Add Cluster** → enter `hvlab-clus01.azrl.mgmt`

### Using PowerShell (Pre-Registration)

```powershell
# On each cluster node — WAC vMode installs a local agent service
# The agent must be pre-approved before the server appears as managed

# Verify WAC vMode agent is installed on each node
Invoke-Command -ComputerName @("hvnode01","hvnode02","hvnode03","hvnode04") -ScriptBlock {
    Get-Service | Where-Object { $_.Name -like "*WACvMode*" -or
                                  $_.DisplayName -like "*Virtualization*Agent*" }
}
```

> The WAC vMode agent on each host is **stateful** and **persistent** — unlike WAC Administration Mode which makes per-session WMI/WinRM connections, WAC vMode agents maintain an ongoing connection to the management server. This enables real-time health monitoring, event streaming, and proactive alerts.

---

## Key Features to Demonstrate

### Feature 1: VM Lifecycle Management

- **Create VM**: Click **New VM** → select host node → set vCPU/RAM/VHDX → deploy
- **VM Console**: Click a VM → **Connect** for in-browser console (no need for separate RDP/VMConnect)
- **VM Settings**: Edit vCPU, RAM, network adapters live (hot-add supported on WS2025 guests)

### Feature 2: Live Migration

1. Select a running VM → click **Move**
2. Choose destination node (e.g., `hvnode02`)
3. Watch the live migration status bar — near-zero downtime
4. Verify the VM is now owned by `hvnode02`

**Talking point**: WAC vMode uses the same live migration infrastructure as SCVMM/VMM but surfaces it in a modern web UI. The Kerberos constrained delegation configured in the AD step is what makes this work without prompting for credentials.

### Feature 3: Storage (CSV) View

- Navigate to **Cluster** → **Storage** → view all 3 CSVs (`CSV-Vol1`, `CSV-Vol2`, `CSV-Vol3`)
- Show capacity, used space, per-volume performance counters
- Demonstrate adding a VM to a specific CSV

### Feature 4: Host Health Dashboard

- Navigate to **Hosts** → click a node → **Overview**
- Show real-time CPU, memory, network, storage utilization
- Show Hyper-V event log inline
- Show NUMA topology (useful for the E104ids_v5 discussion)

### Feature 5: Cluster Events and Alerts

- Navigate to **Cluster** → **Events**
- Show failover events if any were triggered
- Demonstrate creating an alert rule for a node going offline

---

## Troubleshooting

### TLS Certificate Renewal (60-Day Expiry)

During the preview, WAC vMode uses a self-signed certificate that expires every 60 days. When expired, the browser will refuse the connection.

```powershell
# On hvwac01 — check certificate expiry
$cert = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object { $_.Subject -like "*WAC*" -or
                   $_.FriendlyName -like "*Windows Admin Center*" } |
    Sort-Object NotAfter -Descending | Select-Object -First 1

Write-Host "Certificate: $($cert.Subject)"
Write-Host "Expires: $($cert.NotAfter)"
Write-Host "Days remaining: $(($cert.NotAfter - (Get-Date)).Days)"

# If expired — stop WAC vMode service, delete old cert, restart to generate new one
if (($cert.NotAfter - (Get-Date)).Days -lt 5) {
    Write-Host "Certificate expiring soon — renewing..." -ForegroundColor Yellow
    # Stop WAC vMode services
    Get-Service | Where-Object { $_.DisplayName -like "*Windows Admin Center*" } |
        Stop-Service -Force
    # Remove expired cert
    Remove-Item "Cert:\LocalMachine\My\$($cert.Thumbprint)"
    # Restart services — will generate new self-signed cert
    Get-Service | Where-Object { $_.DisplayName -like "*Windows Admin Center*" } |
        Start-Service
    Write-Host "New certificate will be generated on service start" -ForegroundColor Green
}
```

### PostgreSQL Service Check

If WAC vMode fails to start or shows database errors:

```powershell
# Check PostgreSQL service state
$pgService = Get-Service | Where-Object { $_.Name -like "*postgres*" }
Write-Host "PostgreSQL service: $($pgService.Name) — State: $($pgService.Status)"

# Check PostgreSQL event log
Get-WinEvent -LogName Application -MaxEvents 50 |
    Where-Object { $_.ProviderName -like "*postgres*" } |
    Select-Object TimeCreated, Message

# Restart if needed
$pgService | Restart-Service
Start-Sleep 10
$pgService | Get-Service | Select-Object Name, Status
```

### Agent Connectivity Issues (Host Not Showing as Connected)

```powershell
# From hvwac01 — test connectivity to each node
$nodes = @("hvnode01","hvnode02","hvnode03","hvnode04")
foreach ($node in $nodes) {
    $ping = Test-Connection $node -Count 2 -Quiet
    $winrm = Test-WSMan -ComputerName $node -ErrorAction SilentlyContinue
    Write-Host "$node — Ping: $ping  | WinRM: $($null -ne $winrm)"
}

# On the problem node — restart the WAC vMode agent
Invoke-Command -ComputerName "hvnode02" -ScriptBlock {
    Get-Service | Where-Object { $_.Name -like "*WACvMode*" } | Restart-Service
    Start-Sleep 30
    Get-Service | Where-Object { $_.Name -like "*WACvMode*" } | Select-Object Name, Status
}
```

### WAC vMode Not Loading After Reboot

```powershell
# On hvwac01 — check all required services in order
$services = @(
    (Get-Service | Where-Object { $_.Name -like "*postgres*" }),
    (Get-Service | Where-Object { $_.DisplayName -like "*Windows Admin Center*" })
)

foreach ($svc in $services) {
    if ($svc.Status -ne "Running") {
        Write-Host "Starting: $($svc.DisplayName)" -ForegroundColor Yellow
        $svc | Start-Service
        Start-Sleep 15
    }
    Write-Host "✓ $($svc.DisplayName): $($svc.Status)" -ForegroundColor Green
}
```
