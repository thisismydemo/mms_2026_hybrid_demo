##############################################################################
# 03-configure-cluster.ps1  — Create Failover Cluster hvlab-clus01
# Run from: self-hosted runner OR domain-joined machine with Failover Clustering RSAT
##############################################################################

param(
    [string[]]$Nodes           = @('hvnode01','hvnode02','hvnode03','hvnode04'),
    [string]  $ClusterName     = 'hvlab-clus01',
    [string]  $ClusterIP       = '172.16.10.200',
    [string]  $WitnessStorage  = 'sthvlabwitness01',
    [string]  $WitnessRG       = 'rg-hvlab-mms26-eus-01',
    [string]  $WitnessSubId    = '00cd4357-ed45-4efb-bee0-10c467ff994b',
    [string]  $CsvBasePath     = 'C:\ClusterStorage'
)

$ErrorActionPreference = 'Stop'
Import-Module FailoverClusters

Write-Host "=== Creating Failover Cluster $ClusterName ===" -ForegroundColor Cyan

# Run validation (non-destructive)
Write-Host "Running cluster validation..."
$validationReport = Test-Cluster -Node $Nodes -Include 'Storage','Network','Inventory' `
    -ReportName 'C:\hvlab-cluster-validation' -ErrorAction SilentlyContinue
Write-Host "Validation complete. Review C:\hvlab-cluster-validation.htm if needed."

# Create cluster
Write-Host "Creating cluster $ClusterName ($ClusterIP)..."
New-Cluster -Name $ClusterName -Node $Nodes -StaticAddress $ClusterIP `
    -NoStorage

Write-Host "Cluster $ClusterName created."

# Configure Cloud Witness
Write-Host "Configuring Cloud Witness (storage account: $WitnessStorage)..."

# Get storage account key
$storageKey = (az storage account keys list `
    --account-name $WitnessStorage `
    --subscription $WitnessSubId `
    --resource-group $WitnessRG `
    --output json | ConvertFrom-Json)[0].value

Set-ClusterQuorum -Cluster $ClusterName `
    -CloudWitness `
    -AccountName $WitnessStorage `
    -AccessKey $storageKey `
    -EndpointUrl "https://$WitnessStorage.blob.core.windows.net"

Write-Host "  ✅ Cloud Witness configured."

# Add shared disks (iSCSI LUNs)
Write-Host "Adding iSCSI disks to cluster..."
Start-Sleep -Seconds 10   # Wait for disks to be recognized
$availableDisks = Get-ClusterAvailableDisk -Cluster $ClusterName
$availableDisks | Add-ClusterDisk
Write-Host "  Added $($availableDisks.Count) disk(s) to cluster."

# Convert to Cluster Shared Volumes
Write-Host "Converting to Cluster Shared Volumes..."
$clusterDisks = Get-ClusterResource -Cluster $ClusterName -ResourceType 'Physical Disk' |
    Where-Object { $_.Name -notlike '*Witness*' }

$csvNames = @('CSV01','CSV02','CSV03-Templates')
$i = 0
foreach ($disk in $clusterDisks) {
    if ($i -ge $csvNames.Count) { break }
    Add-ClusterSharedVolume -InputObject $disk
    $csv = Get-ClusterSharedVolume -Cluster $ClusterName | Where-Object { $_.Name -like "*$($disk.Name)*" }
    if ($csv) {
        $csv | Set-ClusterParameter -Name FriendlyName -Value $csvNames[$i]
    }
    Write-Host "  ✅ $($csvNames[$i]) added as CSV"
    $i++
}

# Live migration settings
Write-Host "Configuring live migration..."
Invoke-Command -ComputerName $Nodes[0] -ScriptBlock {
    param($ClusterName)
    Set-VMHost -VirtualMachineMigrationEnabled $true
    Set-VMHost -VirtualMachineMigrationAuthenticationType Kerberos
    Set-VMHost -VirtualMachineMigrationPerformanceOption SMB
    # Use Migration NIC (172.16.20.0/24) for live migration traffic
    Add-VMMigrationNetwork -Subnet '172.16.20.0/24' -Priority 1
} -ArgumentList $ClusterName

Write-Host @"

✅ Cluster $ClusterName configured:
   Nodes:   $($Nodes -join ', ')
   IP:      $ClusterIP
   Witness: Cloud ($WitnessStorage)
   CSVs:    CSV01, CSV02, CSV03-Templates

Next: Run configure/04-configure-wac-vmode.ps1 and configure/06-configure-scvmm.ps1
"@
