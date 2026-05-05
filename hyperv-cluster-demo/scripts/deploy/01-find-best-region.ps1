##############################################################################
# 01-find-best-region.ps1
# Check Azure regions for Standard_E104ids_v5 availability and quota.
# Run this BEFORE deployment to pick the optimal region.
#
# Prerequisites:
#   az login --tenant a9b67171-3fbb-45bf-8394-eb56d02a86e4
#   az account set --subscription 00cd4357-ed45-4efb-bee0-10c467ff994b
##############################################################################

param(
    [string[]]$Regions = @('eastus','eastus2','westus2','westus3','centralus','northcentralus','southcentralus'),
    [string]$PreferredSize = 'Standard_E104ids_v5',
    [string[]]$FallbackSizes = @('Standard_E96ds_v5','Standard_E64ds_v5'),
    [string]$SubscriptionId = '00cd4357-ed45-4efb-bee0-10c467ff994b'
)

$ErrorActionPreference = 'Stop'
Write-Host "`n=== HV-Lab Region Discovery ===" -ForegroundColor Cyan
Write-Host "Checking availability of $PreferredSize across $($Regions.Count) regions...`n"

az account set --subscription $SubscriptionId | Out-Null

$results = @()

foreach ($region in $Regions) {
    Write-Host "Checking $region..." -NoNewline

    $sizesToCheck = @($PreferredSize) + $FallbackSizes

    foreach ($size in $sizesToCheck) {
        try {
            # Check if SKU is available in the region
            $skuJson = az vm list-skus `
                --location $region `
                --name $size `
                --all `
                --output json 2>$null | ConvertFrom-Json

            if (-not $skuJson -or $skuJson.Count -eq 0) {
                continue
            }

            $sku = $skuJson[0]

            # Check for restrictions
            $restrictions = $sku.restrictions | Where-Object { $_.type -eq 'Location' }
            $available = ($restrictions.Count -eq 0)

            # Get current quota for the VM family
            $usageJson = az vm list-usage --location $region --output json 2>$null | ConvertFrom-Json
            $edsv5Usage = $usageJson | Where-Object { $_.name.value -like '*EDSv5*' -or $_.name.value -like '*standardEDSv5*' }
            $quotaAvailable = if ($edsv5Usage) { $edsv5Usage.limit - $edsv5Usage.currentValue } else { 'unknown' }

            $results += [PSCustomObject]@{
                Region         = $region
                Size           = $size
                Available      = $available
                QuotaRemaining = $quotaAvailable
                Preferred      = ($size -eq $PreferredSize)
            }

            Write-Host " $size=$( if($available){'✓'}else{'✗'} )" -NoNewline
            break  # Found a result for this region, move on
        }
        catch {
            # Size not available in this region, try next
        }
    }
    Write-Host ""
}

Write-Host "`n=== Results ===" -ForegroundColor Cyan
$results | Sort-Object -Property @{E='Preferred';D=$true}, @{E='Available';D=$true}, Region |
    Format-Table Region, Size, Available, QuotaRemaining -AutoSize

$bestRegion = $results | Where-Object { $_.Available -and $_.Size -eq $PreferredSize } |
    Select-Object -First 1

if ($bestRegion) {
    Write-Host "`n✅ RECOMMENDATION: Deploy to '$($bestRegion.Region)' using $($bestRegion.Size)" -ForegroundColor Green
    Write-Host "   Update variables.yml: azure_platform.region = $($bestRegion.Region)" -ForegroundColor Green
    Write-Host "   Update tplabs.bicepparam: param location = '$($bestRegion.Region)'" -ForegroundColor Green
} else {
    $fallback = $results | Where-Object { $_.Available } | Select-Object -First 1
    if ($fallback) {
        Write-Host "`n⚠️  $PreferredSize not available. Fallback: '$($fallback.Region)' using $($fallback.Size)" -ForegroundColor Yellow
    } else {
        Write-Host "`n❌ No suitable regions found. Request quota increase via Azure Portal." -ForegroundColor Red
        Write-Host "   Portal: https://portal.azure.com/#view/Microsoft_Azure_Capacity/QuotaMenuBlade" -ForegroundColor Red
    }
}
