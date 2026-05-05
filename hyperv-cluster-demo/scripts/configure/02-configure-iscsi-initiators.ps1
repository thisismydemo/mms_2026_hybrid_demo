##############################################################################
# 02-configure-iscsi-initiators.ps1
# Configure MPIO + iSCSI initiators on all 4 cluster nodes
##############################################################################

param(
    [string[]]$ClusterNodes  = @('hvnode01','hvnode02','hvnode03','hvnode04'),
    [string]  $IscsiTarget1  = '172.16.30.10',   # Storage NIC 1 on hviscsi01
    [string]  $IscsiTarget2  = '172.16.30.11',   # Storage NIC 2 on hviscsi01 (MPIO path 2)
    [string]  $TargetIqn     = 'iqn.2025-01.mgmt.azrl:hvlab-cluster-storage'
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Configuring iSCSI Initiators on cluster nodes ===" -ForegroundColor Cyan

foreach ($node in $ClusterNodes) {
    Write-Host "Configuring $node..." -ForegroundColor Yellow
    Invoke-Command -ComputerName $node -ScriptBlock {
        param($Target1, $Target2, $TargetIqn)

        # Enable MPIO and add iSCSI support
        Enable-MSDSMAutomaticClaim -BusType iSCSI
        Add-MSDSMSupportedHW -VendorId MSFT -ProductId MicrosoftVirtualDisk -ErrorAction SilentlyContinue

        # Start iSCSI service
        Set-Service -Name MSiSCSI -StartupType Automatic
        Start-Service MSiSCSI

        # Add portal on storage NIC
        New-IscsiTargetPortal -TargetPortalAddress $Target1
        New-IscsiTargetPortal -TargetPortalAddress $Target2

        # Connect to target (both paths for MPIO)
        Connect-IscsiTarget -NodeAddress $TargetIqn -TargetPortalAddress $Target1 `
            -IsPersistent $true -InitiatorPortalAddress (
                Get-NetIPAddress -AddressFamily IPv4 |
                Where-Object { $_.IPAddress -like '172.16.30.*' } |
                Select-Object -First 1 -ExpandProperty IPAddress
            )
        Connect-IscsiTarget -NodeAddress $TargetIqn -TargetPortalAddress $Target2 `
            -IsPersistent $true -InitiatorPortalAddress (
                Get-NetIPAddress -AddressFamily IPv4 |
                Where-Object { $_.IPAddress -like '172.16.30.*' } |
                Select-Object -First 1 -ExpandProperty IPAddress
            )

        $sessions = Get-IscsiSession | Where-Object { $_.IsConnected }
        Write-Host "  Connected iSCSI sessions: $($sessions.Count)"

    } -ArgumentList $IscsiTarget1, $IscsiTarget2, $TargetIqn
    Write-Host "  ✅ $node iSCSI configured"
}

Write-Host "`niSCSI initiators configured on all nodes. Run 03-configure-cluster.ps1 next."
