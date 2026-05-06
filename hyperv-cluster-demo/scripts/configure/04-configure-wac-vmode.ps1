##############################################################################
# 04-configure-wac-vmode.ps1  — Install WAC Virtualization Mode on hvwac01
#
# CRITICAL: hvwac01 MUST be running Windows Server 2025.
# WAC vmode is separate from WAC Administration Mode.
# Download: https://aka.ms/WACDownloadvMode
##############################################################################

param(
    [string]$WacServer      = 'hvwac01',
    [string]$PgPassword     = '',   # pulled from KV by workflow before running
    [string]$PgUsername     = 'wacadmin',
    [int]   $PgPort         = 5432,
    [int]   $WacPort        = 443,
    [string[]]$ManagedHosts = @('hvnode01','hvnode02','hvnode03','hvnode04','hviscsi01','hvdc01')
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Installing WAC Virtualization Mode on $WacServer ===" -ForegroundColor Cyan

# Verify WS2025 (will fail on WS2022 — save time, check first)
$osVersion = Invoke-Command -ComputerName $WacServer -ScriptBlock {
    (Get-WmiObject Win32_OperatingSystem).Caption
}
if ($osVersion -notlike '*2025*') {
    throw "❌ $WacServer is running '$osVersion' — WAC vmode REQUIRES Windows Server 2025."
}
Write-Host "  ✅ OS verified: $osVersion"

Invoke-Command -ComputerName $WacServer -ScriptBlock {
    param($PgUsername, $PgPassword, $PgPort, $WacPort)

    $installerDir = 'C:\WACvmode'
    New-Item -ItemType Directory -Path $installerDir -Force | Out-Null

    # 1. Install Visual C++ Redistributable prereq
    Write-Host "Installing Visual C++ Redistributable..."
    winget install Microsoft.VCRedist.2015+.x64 --Silent --Accept-Package-Agreements `
        --Accept-Source-Agreements

    # 2. Download WAC vmode installer
    Write-Host "Downloading WAC vmode installer from https://aka.ms/WACDownloadvMode ..."
    $installerPath = "$installerDir\WACvmode.exe"
    Invoke-WebRequest -Uri 'https://aka.ms/WACDownloadvMode' -OutFile $installerPath -UseBasicParsing

    # 3. Install WAC vmode silently
    # Arguments based on WAC vmode install documentation
    Write-Host "Installing WAC vmode (silent)..."
    $installArgs = @(
        '/quiet',
        "/L*v $installerDir\install.log",
        "SME_PORT=$WacPort",
        "PG_PORT=$PgPort",
        "PG_USERNAME=$PgUsername",
        "PG_PASSWORD=$PgPassword"
    )
    Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -NoNewWindow

    # 4. Open firewall for WAC vmode
    New-NetFirewallRule -DisplayName 'WAC vmode HTTPS' -Direction Inbound `
        -Protocol TCP -LocalPort $WacPort -Action Allow -ErrorAction SilentlyContinue

    # 5. Verify service is running
    $svc = Get-Service -Name 'ServerManagementGateway' -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "  ✅ WAC vmode service: $($svc.Status)"
    } else {
        Write-Warning "WAC vmode service not found — check installer log at $installerDir\install.log"
    }

} -ArgumentList $PgUsername, $PgPassword, $PgPort, $WacPort

Write-Host @"

✅ WAC Virtualization Mode installed on $WacServer.

Access URL: https://10.250.2.6
  - Accept the self-signed certificate (60-day expiry during preview)
  - Log in with domain admin credentials (azrl\<admin>)

Add managed hosts manually in the WAC vmode UI, or via API:
  Managed hosts: $($ManagedHosts -join ', ')

Note: WAC vmode uses local agents on each managed host (stateful, not per-session).
Agents are installed automatically when you add a host in the WAC vmode console.
"@
