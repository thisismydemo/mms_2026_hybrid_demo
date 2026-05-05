##############################################################################
# 07-install-arc.ps1  — Install Azure Arc Connected Machine Agent on host VM
#
# Installs on: vm-hvlab-host01-eus-01 (the big nested Hyper-V host)
# NOT on nested VMs — those are internal lab machines, not Arc-managed
#
# Benefits for demo:
#   - Azure Policy compliance visible in portal
#   - Defender for Servers coverage
#   - Azure Monitor / Log Analytics via Arc
#   - Can show Arc-enabled server management as part of hybrid story
#
# Authentication: Uses the VM's managed identity (mi-hvlab-host01-eus-01)
# Run from: self-hosted GitHub runner on the host VM itself
##############################################################################

param(
    [string]$SubscriptionId = '00cd4357-ed45-4efb-bee0-10c467ff994b',
    [string]$TenantId       = 'a9b67171-3fbb-45bf-8394-eb56d02a86e4',
    [string]$ResourceGroup  = 'rg-hvlab-mms26-eus-01',
    [string]$Location       = 'eastus',
    [string]$ArcAgentUrl    = 'https://aka.ms/azcmagent-windows'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
Write-Host "=== Installing Azure Arc Connected Machine Agent ===" -ForegroundColor Cyan

# Check if already installed
$existing = Get-Service -Name himds -ErrorAction SilentlyContinue
if ($existing -and $existing.Status -eq 'Running') {
    Write-Host "  ⏭️  Arc agent already installed and running." -ForegroundColor DarkGray
    azcmagent show
    exit 0
}

# 1. Download Arc agent installer
$installerPath = 'C:\Temp\AzureConnectedMachineAgent.msi'
New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null

Write-Host "  ⬇️  Downloading Arc agent..."
Invoke-WebRequest -Uri $ArcAgentUrl -OutFile $installerPath -UseBasicParsing

# 2. Install silently
Write-Host "  🔧 Installing Arc agent..."
$result = Start-Process msiexec.exe -ArgumentList "/i $installerPath /l*v C:\Temp\ArcInstall.log /quiet" `
    -Wait -NoNewWindow -PassThru
if ($result.ExitCode -ne 0) {
    throw "Arc agent install failed with exit code $($result.ExitCode). See C:\Temp\ArcInstall.log"
}
Write-Host "  ✅ Arc agent installed"

# 3. Connect to Azure using managed identity token (IMDS)
# The VM has a user-assigned managed identity — use it to connect Arc
Write-Host "  🔗 Connecting to Azure Arc using managed identity..."

# Get access token from IMDS
$tokenResponse = Invoke-RestMethod `
    -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F' `
    -Headers @{ Metadata = 'true' }
$accessToken = $tokenResponse.access_token

# Connect agent — service principal mode using MSI token
& 'C:\Program Files\AzureConnectedMachineAgent\azcmagent.exe' connect `
    --subscription-id $SubscriptionId `
    --tenant-id       $TenantId `
    --resource-group  $ResourceGroup `
    --location        $Location `
    --access-token    $accessToken

if ($LASTEXITCODE -ne 0) {
    throw "Arc connect failed with exit code $LASTEXITCODE"
}

# 4. Verify
Write-Host "`n=== Arc Agent Status ===" -ForegroundColor Cyan
& 'C:\Program Files\AzureConnectedMachineAgent\azcmagent.exe' show

Write-Host @"

✅ Azure Arc Connected Machine Agent installed.
   Resource group: $ResourceGroup
   Location:       $Location
   Tenant:         $TenantId

View in portal:
  https://portal.azure.com/#view/Microsoft_Azure_HybridCompute/AzureArcCenterBlade
  → Azure Arc → Servers → rg-hvlab-mms26-eus-01 → hvlabhost01
"@
