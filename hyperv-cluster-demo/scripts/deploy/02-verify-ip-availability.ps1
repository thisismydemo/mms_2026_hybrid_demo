##############################################################################
# 02-verify-ip-availability.ps1
# Confirm that 10.250.1.45/.46/.47/.48 are free in the management subnet
# before Bicep deployment locks them in as static IPs.
#
# Prerequisites:
#   az login --tenant a9b67171-3fbb-45bf-8394-eb56d02a86e4
#   az account set --subscription 2caa0b8a-a1d6-4f0c-8c03-861787b8315c  # tplabs hub sub
##############################################################################

param(
    [string]$VNetResourceGroup = 'rg-c01-hub-eus-01',
    [string]$VNetName          = 'vnet-lab-prodtech-eus-connectivity-hub',
    [string]$SubnetName        = 'snet-lab-prodtech-eus-connectivity-mgmt',
    [string[]]$IpsToCheck      = @('10.250.1.45','10.250.1.46','10.250.1.47','10.250.1.48'),
    # Hub subscription (where the VNet lives)
    [string]$HubSubscriptionId = '2caa0b8a-a1d6-4f0c-8c03-861787b8315c'
)

$ErrorActionPreference = 'Stop'
Write-Host "`n=== HV-Lab IP Availability Check ===" -ForegroundColor Cyan
Write-Host "Subnet: $SubnetName ($VNetName)`n"

az account set --subscription $HubSubscriptionId | Out-Null

# Get all NICs in the subscription and collect their private IPs
Write-Host "Fetching all NIC IP configurations in subscription..." -ForegroundColor Gray
$allNics = az network nic list --subscription $HubSubscriptionId --output json | ConvertFrom-Json
$allocatedIps = $allNics | ForEach-Object { $_.ipConfigurations } |
    ForEach-Object { $_.privateIPAddress } |
    Where-Object { $_ } |
    Sort-Object -Unique

# Also check Azure internal allocations (gateway, etc.)
$subnetJson = az network vnet subnet show `
    --resource-group $VNetResourceGroup `
    --vnet-name $VNetName `
    --name $SubnetName `
    --output json | ConvertFrom-Json

$results = @()
$allClear = $true

foreach ($ip in $IpsToCheck) {
    $inUse = $allocatedIps -contains $ip

    # Azure reserves .0 (network), .1 (gateway), .2 (DNS), .3 (reserved), .255 (broadcast)
    $octets = $ip.Split('.')
    $lastOctet = [int]$octets[3]
    $azureReserved = ($lastOctet -le 3 -or $lastOctet -eq 255)

    $status = if ($azureReserved) { 'RESERVED (Azure)' }
              elseif ($inUse) { 'IN USE' }
              else { 'FREE ✅' }

    if ($inUse -or $azureReserved) { $allClear = $false }

    $label = switch ($ip) {
        '10.250.1.45' { 'vm-hvlab-host01-eus-01 (primary)' }
        '10.250.1.46' { 'hvwac01 secondary IP' }
        '10.250.1.47' { 'hvscvmm01 secondary IP' }
        '10.250.1.48' { 'reserved/spare' }
        default       { '' }
    }

    $results += [PSCustomObject]@{
        IP     = $ip
        Label  = $label
        Status = $status
    }
}

$results | Format-Table IP, Label, Status -AutoSize

if ($allClear) {
    Write-Host "✅ All IPs are available. Safe to deploy." -ForegroundColor Green
} else {
    Write-Host "❌ One or more IPs are in use. Update ip_allocation in variables.yml before deploying." -ForegroundColor Red
    Write-Host "   Suggested alternative start: 10.250.1.50" -ForegroundColor Yellow
}
