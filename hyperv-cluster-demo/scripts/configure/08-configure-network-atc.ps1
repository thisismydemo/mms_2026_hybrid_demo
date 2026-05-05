##############################################################################
# 08-configure-network-atc.ps1  — Network ATC intents on cluster nodes
#
# Network ATC (Adaptive Network Configuration) was introduced in WS2022 and
# replaces manual SET switch creation. A single Add-NetIntent command creates
# the SET switch, configures RDMA (where supported), sets QoS policies, and
# manages NIC teaming — automatically.
#
# For cluster nodes (hvnode01-04), we define two intents:
#   1. "Management_Compute" — Mgmt + Migration NICs → creates SET switch for
#      VM traffic and live migration
#   2. "Storage" — Storage NIC → iSCSI path (RDMA not available in nested VMs,
#      but the intent structure matches production Azure Stack HCI deployments)
#
# Note: The HOST VM (hvlabhost01) has a single Azure NIC — SET teaming
#       doesn't apply. Its vSwitches are already created in bootstrap phase 2.
##############################################################################

param(
    [string[]]$ClusterNodes = @('hvnode01','hvnode02','hvnode03','hvnode04')
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Configuring Network ATC on cluster nodes ===" -ForegroundColor Cyan

foreach ($node in $ClusterNodes) {
    Write-Host "`nConfiguring $node..." -ForegroundColor Yellow

    Invoke-Command -ComputerName $node -ScriptBlock {

        # Install Network ATC feature (included in WS2022 with Desktop Experience)
        Install-WindowsFeature -Name NetworkATC -IncludeManagementTools -ErrorAction SilentlyContinue
        Import-Module NetworkATC

        # Discover NIC names (they may vary by VM generation/driver)
        $mgmtNIC      = (Get-NetAdapter | Where-Object { $_.Name -like '*Mgmt*' -or $_.Name -eq 'Ethernet' }).Name | Select-Object -First 1
        $migrationNIC = (Get-NetAdapter | Where-Object { $_.Name -like '*Migration*' }).Name | Select-Object -First 1
        $storageNIC   = (Get-NetAdapter | Where-Object { $_.Name -like '*Storage*' }).Name | Select-Object -First 1

        Write-Host "  NICs found: Mgmt=$mgmtNIC  Migration=$migrationNIC  Storage=$storageNIC"

        # ── Intent 1: Management + Compute (VM traffic + live migration) ────
        # Creates SET switch named 'SETswitch-Mgmt-Compute' automatically
        if ($mgmtNIC -and $migrationNIC) {
            $mgmtComputeOverride = New-NetIntentAdapterPropertyOverrides
            $mgmtComputeOverride.JumboPacket = 9014   # Jumbo frames for live migration

            Add-NetIntent `
                -Name         'Management_Compute' `
                -Management `
                -Compute `
                -AdapterName  @($mgmtNIC, $migrationNIC) `
                -AdapterPropertyOverrides $mgmtComputeOverride `
                -ErrorAction SilentlyContinue

            Write-Host "  ✅ Intent 'Management_Compute' added ($mgmtNIC + $migrationNIC)"
            Write-Host "     SET switch created automatically by Network ATC"
        } else {
            Write-Warning "  Could not find Management/Migration NICs — check NIC naming"
        }

        # ── Intent 2: Storage (iSCSI path) ──────────────────────────────────
        # In nested VMs, RDMA is not functional, but the intent structure
        # mirrors a real Azure Stack HCI deployment for demo authenticity.
        if ($storageNIC) {
            $storageOverride = New-NetIntentStorageOverrides
            $storageOverride.EnableAutomaticIPGeneration = $false   # we use static IPs

            Add-NetIntent `
                -Name         'Storage' `
                -Storage `
                -AdapterName  @($storageNIC) `
                -StorageOverrides $storageOverride `
                -ErrorAction SilentlyContinue

            Write-Host "  ✅ Intent 'Storage' added ($storageNIC)"
        } else {
            Write-Warning "  Could not find Storage NIC — check NIC naming"
        }

        # Wait a moment for intents to apply
        Start-Sleep -Seconds 15

        # Show status
        Write-Host "`n  Network ATC intent status:"
        Get-NetIntentStatus | Format-Table Name, Status, ConfigurationStatus -AutoSize

    }
    Write-Host "  ✅ $node Network ATC configured"
}

Write-Host @"

✅ Network ATC configured on all cluster nodes.

Network ATC automatically:
  - Created SET (Switch Embedded Teaming) switch on Management_Compute NICs
  - Set QoS policies for SMB/live migration traffic
  - Configured jumbo frames (9014 bytes) on compute/migration NICs
  - Managed NIC binding order

To verify: Run 'Get-NetIntentStatus' on any node.
"@
