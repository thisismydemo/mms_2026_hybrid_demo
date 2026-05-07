##############################################################################
# 05-bootstrap-phase2.ps1
# PHASE 2 — Configure Hyper-V host after reboot:
#   - Create storage pool + D:\ volume from 4 data disks
#   - Create Hyper-V virtual switches
#   - Configure WinNAT for nested VM outbound internet
#   - Configure IP forwarding routes for secondary IPs (.46/.47)
#   - Optionally join the host VM later once the lab-local domain exists
#
# Run via: az vm run-command invoke (from workflow 02, step "Phase 2")
# Parameters passed by workflow: DomainJoinPassword
##############################################################################

param(
    [string]$DomainFqdn          = 'azrl.mgmt',
    [string]$DomainJoinUser      = 'svc-hvlab-deploy',
    [string]$DomainJoinPassword,
    [string]$JoinOU              = 'OU=hvlab-servers,OU=Servers,OU=MGMT,DC=azrl,DC=mgmt',
    [string]$StoragePoolName     = 'HVLabStoragePool',
    [string]$VolumeLabel         = 'HyperVStorage',
    [string]$VolumeLetter        = 'D',
    [string]$NatName             = 'HVLabNAT',
    [string]$NatSubnet           = '172.16.0.0/12'
)

$ErrorActionPreference = 'Stop'
$logFile = 'C:\hvlab-bootstrap-phase2.log'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $logFile -Value $line
    Write-Host $line
}

function New-SecureStringValue {
    param([string]$Value)

    $secureString = New-Object System.Security.SecureString
    foreach ($character in $Value.ToCharArray()) {
        $secureString.AppendChar($character)
    }
    $secureString.MakeReadOnly()
    return $secureString
}

Write-Log "=== HV-Lab Bootstrap Phase 2 — Hyper-V Configuration ==="

# ─────────────────────────────────────────────────────────────────────────────
# 1. Storage Pool — stripe data disks into one pool + D: volume
# ─────────────────────────────────────────────────────────────────────────────
Write-Log "Creating storage pool from data disks..."

$disks = Get-PhysicalDisk | Where-Object {
    $_.CanPool -eq $true -and $_.BusType -eq 'SCSI'
}
Write-Log "Found $($disks.Count) poolable disks."

if ($disks.Count -lt 2) {
    Write-Log "Not enough disks to pool (need at least 2, found $($disks.Count)). Skipping pool creation." 'WARN'
} else {
    $subsystem = Get-StorageSubSystem | Where-Object { $_.FriendlyName -like '*Windows*' }
    $pool = New-StoragePool `
        -FriendlyName $StoragePoolName `
        -StorageSubSystemUniqueId $subsystem.UniqueId `
        -PhysicalDisks $disks `
        -ResiliencySettingNameDefault Simple

    Write-Log "Storage pool '$StoragePoolName' created."

    $vdisk = New-VirtualDisk `
        -StoragePoolFriendlyName $StoragePoolName `
        -FriendlyName 'HVLabVDisk' `
        -UseMaximumSize `
        -ResiliencySettingName Simple `
        -ProvisioningType Fixed

    $vdisk | Initialize-Disk -PartitionStyle GPT -PassThru |
        New-Partition -DriveLetter $VolumeLetter -UseMaximumSize |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel $VolumeLabel -Confirm:$false | Out-Null

    Write-Log "Volume $($VolumeLetter):\ created and formatted as NTFS ($VolumeLabel)."
}

$dirs = @(
    "$($VolumeLetter):\HyperVStorage\VMs",
    "$($VolumeLetter):\HyperVStorage\ISOs",
    "$($VolumeLetter):\HyperVStorage\VHDs"
)
foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
Write-Log "HyperV storage directories created on $($VolumeLetter):\"

# ─────────────────────────────────────────────────────────────────────────────
# 2. Hyper-V Virtual Switches
# ─────────────────────────────────────────────────────────────────────────────
Write-Log "Creating Hyper-V virtual switches..."

$mgmtAdapter = Get-NetAdapter | Where-Object {
    $_.Status -eq 'Up' -and $_.InterfaceDescription -notlike '*Hyper-V*'
} | Sort-Object -Property LinkSpeed -Descending | Select-Object -First 1

Write-Log "Binding vSwitch-External to adapter: $($mgmtAdapter.Name)"
New-VMSwitch -Name 'vSwitch-External' -NetAdapterName $mgmtAdapter.Name `
    -AllowManagementOS $true -Notes 'Bound to Azure NIC — provides Azure subnet access for nested VMs' `
    -ErrorAction SilentlyContinue | Out-Null

$internalSwitches = @(
    @{ Name = 'vSwitch-Mgmt';      IP = '172.16.10.1'; Prefix = 24 },
    @{ Name = 'vSwitch-Migration'; IP = '172.16.20.1'; Prefix = 24 },
    @{ Name = 'vSwitch-Storage';   IP = '172.16.30.1'; Prefix = 24 },
    @{ Name = 'vSwitch-Heartbeat'; IP = '172.16.40.1'; Prefix = 24 },
    @{ Name = 'vSwitch-Workload';  IP = '172.16.50.1'; Prefix = 24 }
)

foreach ($sw in $internalSwitches) {
    New-VMSwitch -Name $sw.Name -SwitchType Internal -ErrorAction SilentlyContinue | Out-Null
    $adapter = Get-NetAdapter | Where-Object { $_.Name -like "*$($sw.Name)*" }
    if ($adapter) {
        New-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $sw.IP -PrefixLength $sw.Prefix `
            -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Log "Created internal switch: $($sw.Name) ($($sw.IP)/$($sw.Prefix))"
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. WinNAT
# ─────────────────────────────────────────────────────────────────────────────
Write-Log "Configuring WinNAT ($NatSubnet)..."
Get-NetNat | Remove-NetNat -Confirm:$false -ErrorAction SilentlyContinue
New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $NatSubnet
Write-Log "WinNAT '$NatName' created for $NatSubnet"

# ─────────────────────────────────────────────────────────────────────────────
# 4. Secondary IP forwarding notes
# ─────────────────────────────────────────────────────────────────────────────
Write-Log "IP forwarding is enabled on Azure NIC (set via Bicep). Host routing handles .6/.7 delivery."
Write-Log "  10.250.2.6 → hvwac01 (assigned to its vNIC on vSwitch-External)"
Write-Log "  10.250.2.7 → hvscvmm01 (assigned to its vNIC on vSwitch-External)"
Write-Log "  Nested VMs must configure their vNICs with these IPs for this to work."

# ─────────────────────────────────────────────────────────────────────────────
# 5. Hyper-V default paths
# ─────────────────────────────────────────────────────────────────────────────
Write-Log "Configuring Hyper-V default VM and VHD paths..."
Set-VMHost -VirtualMachinePath "$($VolumeLetter):\HyperVStorage\VMs" `
           -VirtualHardDiskPath "$($VolumeLetter):\HyperVStorage\VHDs"
Set-VMHost -EnableEnhancedSessionMode $true
Write-Log "Hyper-V paths and enhanced session mode configured."

# ─────────────────────────────────────────────────────────────────────────────
# 6. Optional Domain Join
# ─────────────────────────────────────────────────────────────────────────────
Write-Log "Domain join step for $DomainFqdn..."
if (-not $DomainJoinPassword) {
    Write-Log "DomainJoinPassword not provided — skipping domain join until the lab-local domain is ready." 'WARN'
} else {
    $securePassword = New-SecureStringValue -Value $DomainJoinPassword
    $credential = New-Object System.Management.Automation.PSCredential(
        "$DomainJoinUser@$DomainFqdn", $securePassword)

    Add-Computer -DomainName $DomainFqdn -Credential $credential `
        -OUPath $JoinOU -Restart:$false -Force
    Write-Log "Domain join initiated. A reboot is required to complete."
    New-Item -Path 'C:\hvlab-phase2-complete.marker' -ItemType File -Force | Out-Null
    Write-Log "Phase 2 complete marker created."
}

Write-Log "=== Phase 2 Complete ==="
