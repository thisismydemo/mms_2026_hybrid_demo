##############################################################################
# 01-configure-iscsi.ps1  — Install iSCSI Target role + create LUNs on hviscsi01
# Run from: self-hosted runner via Invoke-Command to hviscsi01
##############################################################################

param(
    [string]$IscsiServer = 'hviscsi01',
    [string]$IqnTarget   = 'iqn.2025-01.mgmt.azrl:hvlab-cluster-storage',
    [string]$LUNBasePath = 'D:\iSCSI'
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Configuring iSCSI Target on $IscsiServer ===" -ForegroundColor Cyan

Invoke-Command -ComputerName $IscsiServer -ScriptBlock {
    param($IqnTarget, $LUNBasePath)

    # Install iSCSI Target Server role
    Install-WindowsFeature -Name FS-iSCSITarget-Server -IncludeManagementTools
    Import-Module IscsiTarget

    New-Item -ItemType Directory -Path $LUNBasePath -Force | Out-Null

    # Create iSCSI Target
    New-IscsiServerTarget -TargetName 'hvlab-cluster' -InitiatorIds @(
        "IQN:iqn.1991-05.com.microsoft:hvnode01*",
        "IQN:iqn.1991-05.com.microsoft:hvnode02*",
        "IQN:iqn.1991-05.com.microsoft:hvnode03*",
        "IQN:iqn.1991-05.com.microsoft:hvnode04*"
    )

    $luns = @(
        @{ Name='quorum';          SizeGB=2;   File='lun0-quorum.vhdx' },
        @{ Name='csv01';           SizeGB=500; File='lun1-csv01.vhdx' },
        @{ Name='csv02';           SizeGB=500; File='lun2-csv02.vhdx' },
        @{ Name='csv03-templates'; SizeGB=500; File='lun3-csv03-templates.vhdx' }
    )

    foreach ($lun in $luns) {
        $vhdPath = Join-Path $LUNBasePath $lun.File
        New-IscsiVirtualDisk -Path $vhdPath -SizeBytes ($lun.SizeGB * 1GB)
        Add-IscsiVirtualDiskTargetMapping -TargetName 'hvlab-cluster' -Path $vhdPath
        Write-Host "  ✅ LUN: $($lun.Name) ($($lun.SizeGB) GB) → $vhdPath"
    }

    # Open iSCSI firewall port
    New-NetFirewallRule -DisplayName 'iSCSI Target' -Direction Inbound `
        -Protocol TCP -LocalPort 3260 -Action Allow -ErrorAction SilentlyContinue

    Write-Host "iSCSI Target configured. IQN: $IqnTarget"
    Write-Host "LUNs: 1 × 2 GB (quorum), 3 × 500 GB (CSV01-03)"

} -ArgumentList $IqnTarget, $LUNBasePath
