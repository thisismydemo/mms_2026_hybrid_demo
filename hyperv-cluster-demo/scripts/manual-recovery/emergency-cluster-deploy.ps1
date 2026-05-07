##############################################################################
# emergency-cluster-deploy.ps1
#
# PURPOSE : Rebuild hvnode01-04 and hvwac01 from WS2025, then form the
#           failover cluster and install WAC vMode.
#           Run DIRECTLY on hv-host01 (RDP or PSRemoting as local admin).
#
# ASSUMES : hvdc01 is UP and is DC for azrl.mgmt
#           hviscsi01 is UP with iSCSI target + LUNs already configured
#           F:\HyperVStorage\ISOs\WS2025.iso exists (run 00-download-isos.ps1 first)
#
# TIME    : ~50-60 min total
#
# USAGE   :
#   # On hv-host01 as administrator:
#   .\emergency-cluster-deploy.ps1
#
#   # To skip WAC install (saves 20 min if only cluster is needed):
#   .\emergency-cluster-deploy.ps1 -SkipWAC
#
#   # Dry-run — show what would be deleted/created, no changes:
#   .\emergency-cluster-deploy.ps1 -WhatIf
##############################################################################
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $IsoPath         = 'F:\HyperVStorage\ISOs\WS2025.iso',
    [string] $VHDBase         = 'F:\HyperVStorage\VMs',
    [string] $DomainFqdn      = 'azrl.mgmt',
    [string] $DomainNetBIOS   = 'AZRL',
    [string] $DomainJoinUser  = 'svc-hvlab-deploy',
    # Leave blank to pull from Key Vault at runtime
    [string] $DomainJoinPass  = '',
    [string] $LocalAdminPass  = 'Temp@dmin2025!',   # temporary, changed after domain join
    [string] $KVName          = 'kv-hvlab-mms26-eus-01',
    [string] $KVSubscription  = '00cd4357-ed45-4efb-bee0-10c467ff994b',
    [string] $ClusterName     = 'hvlab-clus01',
    [string] $ClusterIP       = '172.16.10.200',
    [string] $WitnessStorage  = 'sthvlabwitness01',
    [string] $WitnessRG       = 'rg-hvlab-mms26-eus-01',
    [string] $IscsiTarget1    = '172.16.30.10',
    [string] $IscsiTarget2    = '172.16.30.11',
    [string] $TargetIqn       = 'iqn.2025-01.mgmt.azrl:hvlab-cluster-storage',
    [switch] $SkipWAC,
    [switch] $SkipClusterConfig
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$startTime             = Get-Date

function Write-Step { param([string]$Msg)
    Write-Host "`n$(Get-Date -Format 'HH:mm:ss')  ===  $Msg  ===" -ForegroundColor Cyan }

function Write-OK   { param([string]$Msg)
    Write-Host "  [OK]  $Msg" -ForegroundColor Green }

function Write-Warn { param([string]$Msg)
    Write-Host "  [!!]  $Msg" -ForegroundColor Yellow }

function New-SecureStringValue {
    param([string]$Value)

    $secureString = New-Object System.Security.SecureString
    foreach ($character in $Value.ToCharArray()) {
        $secureString.AppendChar($character)
    }
    $secureString.MakeReadOnly()
    return $secureString
}

function Wait-VMReady {
    param([string[]]$Names, [int]$TimeoutMin = 20)
    Write-Step "Waiting for WinRM on: $($Names -join ', ') (max ${TimeoutMin}m)"
    $deadline  = (Get-Date).AddMinutes($TimeoutMin)
    $remaining = [System.Collections.Generic.List[string]]$Names
    while ($remaining.Count -gt 0 -and (Get-Date) -lt $deadline) {
        $done = @()
        foreach ($n in $remaining) {
            try {
                $ok = Invoke-Command -ComputerName $n -ScriptBlock { $env:COMPUTERNAME } `
                    -ErrorAction SilentlyContinue
                if ($ok) {
                    Write-OK "$n is responding"
                    $done += $n
                }
            } catch { }
        }
        $done | ForEach-Object { $remaining.Remove($_) | Out-Null }
        if ($remaining.Count -gt 0) {
            Write-Host "    Still waiting: $($remaining -join ', ')" -NoNewline
            Start-Sleep -Seconds 30
            Write-Host " ($(([int]((Get-Date)-$startTime).TotalMinutes))m elapsed)"
        }
    }
    if ($remaining.Count -gt 0) {
        Write-Warn "Timed out waiting for: $($remaining -join ', ')"
        Write-Warn "Check VM console — OS install may still be in progress"
    }
}

#─────────────────────────────────────────────────────────────────────────────
# NODE LAYOUT
#─────────────────────────────────────────────────────────────────────────────
$nodeConfig = @(
    @{ Name='hvnode01'; MgmtIP='172.16.10.21'; MigIP='172.16.20.21'; StorIP='172.16.30.21'; HbIP='172.16.40.21' },
    @{ Name='hvnode02'; MgmtIP='172.16.10.22'; MigIP='172.16.20.22'; StorIP='172.16.30.22'; HbIP='172.16.40.22' },
    @{ Name='hvnode03'; MgmtIP='172.16.10.23'; MigIP='172.16.20.23'; StorIP='172.16.30.23'; HbIP='172.16.40.23' },
    @{ Name='hvnode04'; MgmtIP='172.16.10.24'; MigIP='172.16.20.24'; StorIP='172.16.30.24'; HbIP='172.16.40.24' }
)
$wacConfig = @{
    Name       = 'hvwac01'
    MgmtIP     = '172.16.10.30'
    ExternalIP = '10.250.2.6'
    vCPUs      = 4
    MemoryGB   = 16
    OSDiskGB   = 80
}
$nodeVMs    = $nodeConfig | ForEach-Object { $_.Name }
$allTargets = $nodeVMs + @($wacConfig.Name)

#─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT
#─────────────────────────────────────────────────────────────────────────────
Write-Step "Pre-flight checks"

# ISO
if (-not (Test-Path $IsoPath)) {
    Write-Host "WS2025 ISO not found at $IsoPath" -ForegroundColor Red
    Write-Host "Attempting blob download from sthvlabisomms26 ..."
    $storKey = az storage account keys list --account-name sthvlabisomms26 `
        --resource-group $WitnessRG --subscription $KVSubscription `
        --query "[0].value" -o tsv
    az storage blob download `
        --account-name sthvlabisomms26 --container-name isos `
        --name WS2025.iso --file $IsoPath `
        --account-key $storKey | Out-Null
    if (-not (Test-Path $IsoPath)) {
        throw "Cannot find or download WS2025.iso. Aborting."
    }
}
Write-OK "WS2025 ISO: $IsoPath ($([math]::Round((Get-Item $IsoPath).Length/1GB,1)) GB)"

# Domain join password
if (-not $DomainJoinPass) {
    Write-Host "  Pulling domain join password from Key Vault $KVName ..."
    $DomainJoinPass = az keyvault secret show `
        --vault-name $KVName --subscription $KVSubscription `
        --name 'hvlab-domain-admin-password' --query value -o tsv
    if (-not $DomainJoinPass) {
        throw "Could not retrieve hvlab-domain-admin-password from $KVName. Aborting."
    }
}
Write-OK "Domain join credentials: $DomainNetBIOS\$DomainJoinUser"

# Hyper-V
if (-not (Get-WindowsFeature -Name Hyper-V).Installed) {
    throw "Hyper-V not installed on this host. Run bootstrap workflows first."
}

# Check vSwitches exist
$reqSwitches = @('vSwitch-Mgmt','vSwitch-External','vSwitch-Migration','vSwitch-Storage','vSwitch-Heartbeat','vSwitch-Workload')
foreach ($sw in $reqSwitches) {
    if (-not (Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue)) {
        throw "vSwitch '$sw' not found. Run bootstrap phase 2 first."
    }
}
Write-OK "All required vSwitches present"

#─────────────────────────────────────────────────────────────────────────────
# UNATTEND VHDX FACTORY
# Creates a tiny FAT32 VHDX with unattend.xml for automated OS install.
# Gen2 Hyper-V VMs detect any drive with \unattend.xml at root during setup.
#─────────────────────────────────────────────────────────────────────────────
function New-UnattendVHDX {
    param(
        [string]$ComputerName,
        [string]$AdminPassword,
        [string]$OutPath
    )

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE"
               processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup"
               processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <DiskConfiguration>
        <Disk wcm:action="add">
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order><Type>EFI</Type><Size>100</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order><Type>MSR</Type><Size>128</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>3</Order><Type>Primary</Type><Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order><PartitionID>1</PartitionID>
              <Format>FAT32</Format><Label>System</Label>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order><PartitionID>3</PartitionID>
              <Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter>
            </ModifyPartition>
          </ModifyPartitions>
          <DiskID>0</DiskID><WillWipeDisk>true</WillWipeDisk>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add">
              <Key>/IMAGE/INDEX</Key>
              <Value>2</Value>
            </MetaData>
          </InstallFrom>
          <InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>
        </OSImage>
      </ImageInstall>
      <UserData>
        <ProductKey><WillShowUI>OnError</WillShowUI></ProductKey>
        <AcceptEula>true</AcceptEula>
      </UserData>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <ComputerName>$ComputerName</ComputerName>
      <TimeZone>UTC</TimeZone>
    </component>
    <component name="Microsoft-Windows-TerminalServices-LocalSessionManager"
               processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <fDenyTSConnections>false</fDenyTSConnections>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <AutoLogon>
        <Password><Value>$AdminPassword</Value><PlainText>true</PlainText></Password>
        <Enabled>true</Enabled><LogonCount>1</LogonCount>
        <Username>Administrator</Username>
      </AutoLogon>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <SkipMachineOOBE>true</SkipMachineOOBE>
        <SkipUserOOBE>true</SkipUserOOBE>
        <NetworkLocation>Work</NetworkLocation>
      </OOBE>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>cmd /c winrm quickconfig -q</CommandLine>
          <Description>Enable WinRM</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>2</Order>
          <CommandLine>cmd /c winrm set winrm/config/service/auth @{Basic="true"}</CommandLine>
          <Description>Allow Basic Auth (for initial bootstrap)</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>3</Order>
          <CommandLine>cmd /c netsh advfirewall firewall set rule group="Windows Remote Management" new enable=yes</CommandLine>
          <Description>WinRM firewall</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>4</Order>
          <CommandLine>cmd /c netsh advfirewall firewall set rule group="Remote Desktop" new enable=yes</CommandLine>
          <Description>RDP firewall</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>5</Order>
          <CommandLine>cmd /c reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f</CommandLine>
          <Description>Allow remote admin</Description>
        </SynchronousCommand>
      </FirstLogonCommands>
      <UserAccounts>
        <AdministratorPassword>
          <Value>$AdminPassword</Value><PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>
    </component>
  </settings>
</unattend>
"@

    # Create a tiny FAT32 VHDX — Windows Setup will find unattend.xml on any drive
    $tmpVHDX = $OutPath
    New-VHD -Path $tmpVHDX -SizeBytes 16MB -Fixed | Out-Null

    $disk = Mount-VHD -Path $tmpVHDX -PassThru | Get-Disk
    Initialize-Disk -InputObject $disk -PartitionStyle MBR -PassThru |
        New-Partition -UseMaximumSize -AssignDriveLetter |
        Format-Volume -FileSystem FAT32 -NewFileSystemLabel 'unattend' -Confirm:$false | Out-Null

    $volume  = Get-Disk | Where-Object Path -eq $disk.Path |
                   Get-Partition | Where-Object DriveLetter | Get-Volume
    $letter  = $volume.DriveLetter
    $xml | Set-Content -Path "${letter}:\unattend.xml" -Encoding UTF8
    Dismount-VHD -Path $tmpVHDX
}

#─────────────────────────────────────────────────────────────────────────────
# PHASE 1 — REMOVE OLD WS2022 VMs
#─────────────────────────────────────────────────────────────────────────────
Write-Step "Phase 1 — Remove old WS2022 VMs"

foreach ($name in $allTargets) {
    $vm = Get-VM -Name $name -ErrorAction SilentlyContinue
    if ($vm) {
        Write-Host "  Found existing VM: $name (State=$($vm.State))"
        if ($PSCmdlet.ShouldProcess($name, "Stop and remove VM")) {
            if ($vm.State -ne 'Off') {
                Stop-VM -Name $name -Force -TurnOff
                Write-OK "$name stopped"
            }
            Remove-VM -Name $name -Force
            Write-OK "$name removed"
        }
    } else {
        Write-Host "  $name — not found (will create fresh)" -ForegroundColor DarkGray
    }

    # Remove old VHDs (keep iSCSI data disks on hviscsi01 if it exists)
    $vmDir = Join-Path $VHDBase $name
    if (Test-Path $vmDir) {
        $vhds = Get-ChildItem $vmDir -Filter '*.vhdx'
        foreach ($vhd in $vhds) {
            if ($PSCmdlet.ShouldProcess($vhd.FullName, "Delete VHDX")) {
                Remove-Item $vhd.FullName -Force
                Write-OK "Deleted $($vhd.Name)"
            }
        }
    }
}

#─────────────────────────────────────────────────────────────────────────────
# PHASE 2 — CREATE NEW VMs WITH WS2025 + UNATTEND
# All VMs boot in parallel to save time.
#─────────────────────────────────────────────────────────────────────────────
Write-Step "Phase 2 — Create new WS2025 VMs (booting in parallel)"

$unattendDir = 'F:\HyperVStorage\unattend'
New-Item -ItemType Directory -Path $unattendDir -Force | Out-Null

foreach ($node in $nodeConfig) {
    $vmDir       = Join-Path $VHDBase $node.Name
    $osDisk      = Join-Path $vmDir "$($node.Name)-os.vhdx"
    $unattendVHD = Join-Path $unattendDir "$($node.Name)-unattend.vhdx"

    New-Item -ItemType Directory -Path $vmDir -Force | Out-Null

    Write-Host "  Creating unattend VHDX for $($node.Name) ..."
    New-UnattendVHDX -ComputerName $node.Name -AdminPassword $LocalAdminPass `
        -OutPath $unattendVHD

    Write-Host "  Creating OS disk for $($node.Name) (80 GB dynamic) ..."
    New-VHD -Path $osDisk -SizeBytes 80GB -Dynamic | Out-Null

    if ($PSCmdlet.ShouldProcess($node.Name, "Create Hyper-V VM")) {
        $vm = New-VM -Name $node.Name -Generation 2 `
            -MemoryStartupBytes 64GB -VHDPath $osDisk -SwitchName 'vSwitch-Mgmt'

        Set-VMProcessor -VM $vm -Count 16 -ExposeVirtualizationExtensions $true
        Set-VMMemory    -VM $vm -DynamicMemoryEnabled $false
        Set-VMFirmware  -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows

        # Additional NICs
        Add-VMNetworkAdapter -VM $vm -SwitchName 'vSwitch-Migration' -Name 'Migration'
        Add-VMNetworkAdapter -VM $vm -SwitchName 'vSwitch-Storage'   -Name 'Storage'
        Add-VMNetworkAdapter -VM $vm -SwitchName 'vSwitch-Heartbeat' -Name 'Heartbeat'
        Add-VMNetworkAdapter -VM $vm -SwitchName 'vSwitch-Workload'  -Name 'Workload'

        # Enable MAC spoofing on Workload NIC for nested VM traffic
        Get-VMNetworkAdapter -VM $vm -Name 'Workload' | Set-VMNetworkAdapter -MacAddressSpoofing On

        # Attach ISO and unattend VHDX
        $dvd     = Add-VMDvdDrive  -VM $vm -Path $IsoPath -PassThru
        Add-VMHardDiskDrive -VM $vm -Path $unattendVHD   # setup finds unattend.xml here

        # Boot order: ISO first, then OS disk
        $osDrive = Get-VMHardDiskDrive -VM $vm | Where-Object Path -eq $osDisk
        Set-VMFirmware -VM $vm -BootOrder $dvd, $osDrive

        Start-VM -VM $vm
        Write-OK "$($node.Name) created and started (WS2025 install in progress)"
    }
}

# WAC vMode VM
if (-not $SkipWAC) {
    $wacName     = $wacConfig.Name
    $wacDir      = Join-Path $VHDBase $wacName
    $wacOsDisk   = Join-Path $wacDir "$wacName-os.vhdx"
    $wacUnattend = Join-Path $unattendDir "$wacName-unattend.vhdx"

    New-Item -ItemType Directory -Path $wacDir -Force | Out-Null

    Write-Host "  Creating unattend VHDX for $wacName ..."
    New-UnattendVHDX -ComputerName $wacName -AdminPassword $LocalAdminPass `
        -OutPath $wacUnattend

    New-VHD -Path $wacOsDisk -SizeBytes ($wacConfig.OSDiskGB * 1GB) -Dynamic | Out-Null

    if ($PSCmdlet.ShouldProcess($wacName, "Create Hyper-V VM")) {
        $wacVM = New-VM -Name $wacName -Generation 2 `
            -MemoryStartupBytes ($wacConfig.MemoryGB * 1GB) `
            -VHDPath $wacOsDisk -SwitchName 'vSwitch-External'

        Set-VMProcessor -VM $wacVM -Count $wacConfig.vCPUs
        Set-VMMemory    -VM $wacVM -DynamicMemoryEnabled $false
        Set-VMFirmware  -VM $wacVM -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows

        Add-VMNetworkAdapter -VM $wacVM -SwitchName 'vSwitch-Mgmt' -Name 'Mgmt'

        $wacDvd     = Add-VMDvdDrive  -VM $wacVM -Path $IsoPath -PassThru
        Add-VMHardDiskDrive -VM $wacVM -Path $wacUnattend
        $wacOsDrive = Get-VMHardDiskDrive -VM $wacVM | Where-Object Path -eq $wacOsDisk
        Set-VMFirmware -VM $wacVM -BootOrder $wacDvd, $wacOsDrive

        Start-VM -VM $wacVM
        Write-OK "$wacName created and started (WS2025 install in progress)"
    }
}

Write-Host @"

  All VMs are now installing WS2025 in parallel.
  Typical install time: 12-18 minutes.
  You can watch progress in Hyper-V Manager or via VM console.
  Script will continue polling every 30 seconds...
"@ -ForegroundColor Yellow

#─────────────────────────────────────────────────────────────────────────────
# PHASE 3 — WAIT FOR OS INSTALL, THEN CONFIGURE NETWORKING
#─────────────────────────────────────────────────────────────────────────────
Write-Step "Phase 3 — Waiting for WinRM on all nodes"

# Add host to TrustedHosts so we can WinRM to nested VMs over 172.16.10.0/24
$current = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
if ($current -notlike '*172.16.*') {
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value '172.16.*,10.250.2.*' -Force
    Write-OK "WSMan TrustedHosts updated"
}

# The unattend sets the hostname but the initial IP is DHCP/APIPA on vSwitch-Mgmt.
# We wait for them to appear on the Mgmt subnet via Hyper-V guest network or try IPs.
# Actually — reach by VM name via Hyper-V VMNetwork address lookup.

function Get-VMGuestIP {
    param([string]$VMName, [string]$NICName = 'Network Adapter')
    $nic = Get-VMNetworkAdapter -VMName $VMName | Where-Object {
        $_.SwitchName -eq 'vSwitch-Mgmt'
    } | Select-Object -First 1
    if ($nic) { return ($nic.IPAddresses | Where-Object { $_ -match '^172\.16\.' } | Select-Object -First 1) }
}

$allVMNames = if ($SkipWAC) { $nodeVMs } else { $nodeVMs + @($wacConfig.Name) }

Write-Host "  Waiting for VMs to complete OS install and first boot (~15 min) ..."
$deadline  = (Get-Date).AddMinutes(25)
$readyMap  = @{}

while ($readyMap.Count -lt $allVMNames.Count -and (Get-Date) -lt $deadline) {
    foreach ($vmName in $allVMNames) {
        if ($readyMap[$vmName]) { continue }
        $vmState = (Get-VM -Name $vmName).State
        if ($vmState -eq 'Off') {
            # VM may have shut down after initial boot - restart it
            Write-Warn "$vmName shut down — restarting (normal after first boot specialize)"
            Start-VM -Name $vmName
            Start-Sleep -Seconds 10
            continue
        }
        # Try to connect using the Hyper-V guest IP (populated once DHCP or link-local runs)
        $ip = Get-VMGuestIP -VMName $vmName
        if ($ip) {
            $cred = New-Object PSCredential('Administrator', (New-SecureStringValue -Value $LocalAdminPass))
            try {
                $hostname = Invoke-Command -ComputerName $ip -Credential $cred `
                    -ScriptBlock { $env:COMPUTERNAME } -ErrorAction SilentlyContinue
                if ($hostname) {
                    Write-OK "$vmName is up (IP=$ip, hostname=$hostname)"
                    $readyMap[$vmName] = $ip
                }
            } catch { }
        }
    }
    if ($readyMap.Count -lt $allVMNames.Count) {
        $waiting = $allVMNames | Where-Object { -not $readyMap[$_] }
        Write-Host "  Still waiting: $($waiting -join ', ')  ($(([int]((Get-Date)-$startTime).TotalMinutes))m elapsed)"
        Start-Sleep -Seconds 30
    }
}

if ($readyMap.Count -lt $allVMNames.Count) {
    Write-Warn "Not all VMs responded. Proceeding with those that are ready."
    Write-Warn "You may need to complete the remaining VMs manually."
}

Write-Step "Phase 3b — Setting static IPs and hostnames via WinRM"

$cred = New-Object PSCredential('Administrator', (New-SecureStringValue -Value $LocalAdminPass))

foreach ($node in $nodeConfig) {
    $ip = $readyMap[$node.Name]
    if (-not $ip) { Write-Warn "$($node.Name) — skipping (not ready)"; continue }

    Write-Host "  Configuring network on $($node.Name) (via $ip) ..."
    Invoke-Command -ComputerName $ip -Credential $cred -ArgumentList $node -ScriptBlock {
        param($n)
        # Mgmt NIC
        $mgmtAdapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } |
            Sort-Object ifIndex | Select-Object -First 1
        $mgmtAdapter | New-NetIPAddress -IPAddress $n.MgmtIP -PrefixLength 24 `
            -DefaultGateway '172.16.10.1' -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $mgmtAdapter.ifIndex `
            -ServerAddresses '172.16.10.10' -ErrorAction SilentlyContinue

        # Migration NIC
        $migAdapters = Get-NetAdapter | Where-Object {
            $_.Status -eq 'Up' -and $_.Name -like '*Migration*' -or
            ($_.Status -eq 'Up' -and $_.MacAddress -and
            (Get-NetIPConfiguration -InterfaceIndex $_.ifIndex).IPv4Address.IPAddress -notmatch '172.16.10')
        } | Select-Object -Skip 1 -First 1
        if ($migAdapters) {
            $migAdapters | New-NetIPAddress -IPAddress $n.MigIP -PrefixLength 24 `
                -ErrorAction SilentlyContinue | Out-Null
        }

        # Storage NIC
        $storAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } |
            Sort-Object ifIndex | Select-Object -Skip 2 -First 1
        if ($storAdapters) {
            $storAdapters | New-NetIPAddress -IPAddress $n.StorIP -PrefixLength 24 `
                -ErrorAction SilentlyContinue | Out-Null
        }

        # Heartbeat NIC
        $hbAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } |
            Sort-Object ifIndex | Select-Object -Skip 3 -First 1
        if ($hbAdapters) {
            $hbAdapters | New-NetIPAddress -IPAddress $n.HbIP -PrefixLength 24 `
                -ErrorAction SilentlyContinue | Out-Null
        }

        # Enable RDP
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
            -Name fDenyTSConnections -Value 0

        Write-Host "Network configured on $env:COMPUTERNAME"
    }
    Write-OK "$($node.Name) — static IPs set"
}

# WAC VM networking
if (-not $SkipWAC) {
    $wacIp = $readyMap[$wacConfig.Name]
    if ($wacIp) {
        Invoke-Command -ComputerName $wacIp -Credential $cred -ArgumentList $wacConfig -ScriptBlock {
            param($wac)
            # External NIC (vSwitch-External) — gets Azure IP 10.250.2.6
            $extAdapter = Get-NetAdapter | Sort-Object ifIndex | Select-Object -First 1
            $extAdapter | New-NetIPAddress -IPAddress $wac.ExternalIP -PrefixLength 27 `
                -DefaultGateway '10.250.2.1' -ErrorAction SilentlyContinue | Out-Null
            Set-DnsClientServerAddress -InterfaceIndex $extAdapter.ifIndex `
                -ServerAddresses '172.16.10.10' -ErrorAction SilentlyContinue

            # Mgmt NIC (vSwitch-Mgmt) — internal 172.16.10.30
            $mgmtAdapter = Get-NetAdapter | Sort-Object ifIndex | Select-Object -Skip 1 -First 1
            if ($mgmtAdapter) {
                $mgmtAdapter | New-NetIPAddress -IPAddress $wac.MgmtIP -PrefixLength 24 `
                    -ErrorAction SilentlyContinue | Out-Null
            }
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
                -Name fDenyTSConnections -Value 0
            Write-Host "WAC network configured"
        }
        Write-OK "hvwac01 — static IPs set (Ext=$($wacConfig.ExternalIP), Mgmt=$($wacConfig.MgmtIP))"
    }
}

#─────────────────────────────────────────────────────────────────────────────
# PHASE 4 — INSTALL HYPER-V + FAILOVER CLUSTERING ROLES, THEN DOMAIN JOIN
#─────────────────────────────────────────────────────────────────────────────
Write-Step "Phase 4 — Install roles + domain join (parallel on all nodes)"

$djSecure = New-SecureStringValue -Value $DomainJoinPass
$djCred   = New-Object PSCredential("$DomainNetBIOS\$DomainJoinUser", $djSecure)

$nodeIPs = $nodeConfig | ForEach-Object {
    if ($readyMap[$_.Name]) { $readyMap[$_.Name] } else { $_.MgmtIP }
}

Invoke-Command -ComputerName $nodeIPs -Credential $cred `
    -ArgumentList $DomainFqdn, $DomainNetBIOS, $DomainJoinUser, $DomainJoinPass -ScriptBlock {
    param($domain, $netbios, $djUser, $djPass)

    Write-Host "$env:COMPUTERNAME — Installing Failover Clustering + Hyper-V roles ..."
    $features = @('Failover-Clustering','Hyper-V','RSAT-Clustering','RSAT-Hyper-V-Tools',
                   'Multipath-IO','iSCSI-Target-Server')
    Install-WindowsFeature -Name $features -IncludeManagementTools -Restart:$false | Out-Null
    Write-Host "$env:COMPUTERNAME — Roles installed"

    # Domain join (will trigger reboot — we catch this)
    $secPwd = New-SecureStringValue -Value $djPass
    $cred   = New-Object PSCredential("$netbios\$djUser", $secPwd)
    Add-Computer -DomainName $domain -Credential $cred `
        -OUPath 'OU=hvlab-servers,OU=Servers,OU=MGMT,DC=azrl,DC=mgmt' `
        -Restart -Force

} -AsJob | Wait-Job | Out-Null

Write-OK "Domain join + role install commands sent (nodes rebooting)"
Write-Host "  Waiting 60 seconds for reboots to initiate ..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

Write-Step "Waiting for nodes to come back online after domain join reboot"

# After domain join reboot, use domain credentials to connect
$deadline = (Get-Date).AddMinutes(10)
$onlineNodes = @()
while ($onlineNodes.Count -lt $nodeConfig.Count -and (Get-Date) -lt $deadline) {
    $onlineNodes = @()
    foreach ($node in $nodeConfig) {
        try {
            $result = Invoke-Command -ComputerName $node.Name -Credential $djCred `
                -ScriptBlock { $env:COMPUTERNAME } -ErrorAction SilentlyContinue
            if ($result) { $onlineNodes += $node.Name }
        } catch { }
    }
    if ($onlineNodes.Count -lt $nodeConfig.Count) {
        $missing = $nodeVMs | Where-Object { $_ -notin $onlineNodes }
        Write-Host "  Back online: $($onlineNodes -join ', ')  |  Waiting: $($missing -join ', ')  ($(([int]((Get-Date)-$startTime).TotalMinutes))m)"
        Start-Sleep -Seconds 20
    }
}
Write-OK "Nodes back online: $($onlineNodes -join ', ')"

if (-not $SkipWAC) {
    # Domain join WAC VM
    $wacIp = $readyMap[$wacConfig.Name]
    if ($wacIp) {
        Write-Host "  Domain joining hvwac01 ..."
        Invoke-Command -ComputerName $wacIp -Credential $cred `
            -ArgumentList $DomainFqdn, $DomainNetBIOS, $DomainJoinUser, $DomainJoinPass -ScriptBlock {
            param($domain, $netbios, $djUser, $djPass)
            Install-WindowsFeature -Name @('RSAT-AD-Tools','GPMC') | Out-Null
            $secPwd = New-SecureStringValue -Value $djPass
            $djCred = New-Object PSCredential("$netbios\$djUser", $secPwd)
            Add-Computer -DomainName $domain -Credential $djCred -Restart -Force
        }
        Write-OK "hvwac01 — domain join initiated"
    }
}

#─────────────────────────────────────────────────────────────────────────────
# PHASE 5 — iSCSI INITIATORS + FAILOVER CLUSTER
#─────────────────────────────────────────────────────────────────────────────
if (-not $SkipClusterConfig) {
    Write-Step "Phase 5 — Configure iSCSI initiators on cluster nodes"

    Invoke-Command -ComputerName $nodeVMs -Credential $djCred `
        -ArgumentList $IscsiTarget1, $IscsiTarget2, $TargetIqn -ScriptBlock {
        param($target1, $target2, $iqn)

        # MPIO
        Enable-MSDSMAutomaticClaim -BusType iSCSI -ErrorAction SilentlyContinue
        Add-MSDSMSupportedHW -VendorId MSFT -ProductId MicrosoftVirtualDisk `
            -ErrorAction SilentlyContinue

        # iSCSI service
        Set-Service MSiSCSI -StartupType Automatic
        Start-Service MSiSCSI

        New-IscsiTargetPortal -TargetPortalAddress $target1 -ErrorAction SilentlyContinue
        New-IscsiTargetPortal -TargetPortalAddress $target2 -ErrorAction SilentlyContinue

        Connect-IscsiTarget -NodeAddress $iqn -TargetPortalAddress $target1 `
            -IsPersistent $true -ErrorAction SilentlyContinue
        Connect-IscsiTarget -NodeAddress $iqn -TargetPortalAddress $target2 `
            -IsPersistent $true -ErrorAction SilentlyContinue

        $sessions = Get-IscsiSession | Where-Object IsConnected
        Write-Host "$env:COMPUTERNAME — $($sessions.Count) iSCSI sessions connected"
    }
    Write-OK "iSCSI initiators configured"

    Write-Step "Phase 5b — Create Failover Cluster $ClusterName"

    # Create cluster from the first node
    Invoke-Command -ComputerName $nodeVMs[0] -Credential $djCred `
        -ArgumentList $ClusterName, $ClusterIP, $nodeVMs -ScriptBlock {
        param($name, $ip, $nodes)
        Import-Module FailoverClusters

        Write-Host "Creating cluster $name ($ip) with nodes: $($nodes -join ', ')"
        New-Cluster -Name $name -Node $nodes -StaticAddress $ip -NoStorage
        Write-Host "Cluster $name created"
    }
    Write-OK "Cluster $ClusterName created"

    Write-Step "Phase 5c — Cloud Witness + Add iSCSI disks as CSVs"

    $storKey = az storage account keys list `
        --account-name $WitnessStorage `
        --resource-group $WitnessRG `
        --subscription $KVSubscription `
        --output json | ConvertFrom-Json | Select-Object -First 1 -ExpandProperty value

    Invoke-Command -ComputerName $nodeVMs[0] -Credential $djCred `
        -ArgumentList $ClusterName, $WitnessStorage, $storKey -ScriptBlock {
        param($cluster, $storAcct, $key)
        Import-Module FailoverClusters

        # Cloud Witness
        Set-ClusterQuorum -Cluster $cluster -CloudWitness `
            -AccountName $storAcct -AccessKey $key `
            -EndpointUrl "https://$storAcct.blob.core.windows.net"
        Write-Host "Cloud Witness configured"

        # Wait for iSCSI disks to appear
        Write-Host "Waiting 15s for shared disks to be recognised ..."
        Start-Sleep -Seconds 15

        $avail = Get-ClusterAvailableDisk -Cluster $cluster
        Write-Host "$($avail.Count) disk(s) available to cluster"
        $avail | Add-ClusterDisk

        # Convert physical disks (skip quorum) to CSV
        $csvNames = @('CSV01-Data','CSV02-Data','CSV03-Templates')
        $i = 0
        Get-ClusterResource -Cluster $cluster -ResourceType 'Physical Disk' |
            Where-Object { $_.Name -notlike '*Witness*' } | ForEach-Object {
                if ($i -lt $csvNames.Count) {
                    Add-ClusterSharedVolume -InputObject $_
                    # Rename the CSV directory on the cluster
                    $clusterDisk = Get-ClusterSharedVolume -Cluster $cluster |
                        Where-Object { $_.Name -like "*$($_.Name)*" } | Select-Object -Last 1
                    Write-Host "  Added CSV: $($csvNames[$i])"
                    $i++
                }
            }
        Write-Host "CSVs added: $i volume(s)"
    }
    Write-OK "Cloud Witness + CSVs configured"

    # Live migration settings
    Invoke-Command -ComputerName $nodeVMs -Credential $djCred -ScriptBlock {
        Set-VMHost -VirtualMachineMigrationEnabled $true
        Set-VMHost -VirtualMachineMigrationAuthenticationType Kerberos
        Set-VMHost -VirtualMachineMigrationPerformanceOption SMB
        Add-VMMigrationNetwork -Subnet '172.16.20.0/24' -Priority 1 -ErrorAction SilentlyContinue
        Write-Host "$env:COMPUTERNAME — live migration configured"
    }
    Write-OK "Live migration configured on all nodes"

    # Network ATC
    Invoke-Command -ComputerName $nodeVMs -Credential $djCred -ScriptBlock {
        Install-WindowsFeature -Name NetworkATC -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
        Import-Module NetworkATC

        $mgmtNIC = (Get-NetAdapter | Where-Object { $_.Name -like '*Mgmt*' -or $_.ifIndex -eq 5 } | Select-Object -First 1).Name
        $migNIC  = (Get-NetAdapter | Where-Object { $_.Name -like '*Migration*' } | Select-Object -First 1).Name
        $storNIC = (Get-NetAdapter | Where-Object { $_.Name -like '*Storage*'   } | Select-Object -First 1).Name

        if ($mgmtNIC -and $migNIC) {
            $ov = New-NetIntentAdapterPropertyOverrides
            $ov.JumboPacket = 9014
            Add-NetIntent -Name 'Management_Compute' -Management -Compute `
                -AdapterName @($mgmtNIC,$migNIC) -AdapterPropertyOverrides $ov `
                -ErrorAction SilentlyContinue
        }
        if ($storNIC) {
            $sov = New-NetIntentStorageOverrides
            $sov.EnableAutomaticIPGeneration = $false
            Add-NetIntent -Name 'Storage' -Storage -AdapterName @($storNIC) `
                -StorageOverrides $sov -ErrorAction SilentlyContinue
        }
        Write-Host "$env:COMPUTERNAME — Network ATC intents set"
    }
    Write-OK "Network ATC configured"
}

#─────────────────────────────────────────────────────────────────────────────
# PHASE 6 — WAC vMode INSTALL (runs in background)
#─────────────────────────────────────────────────────────────────────────────
if (-not $SkipWAC) {
    # Wait for hvwac01 to rejoin after domain-join reboot
    Write-Step "Phase 6 — WAC vMode install on hvwac01"
    Write-Host "  Waiting for hvwac01 to come back online after domain join ..."

    $wacOnline = $false
    $deadline  = (Get-Date).AddMinutes(8)
    while (-not $wacOnline -and (Get-Date) -lt $deadline) {
        try {
            Invoke-Command -ComputerName $wacConfig.Name -Credential $djCred `
                -ScriptBlock { $env:COMPUTERNAME } -ErrorAction SilentlyContinue | Out-Null
            $wacOnline = $true
        } catch { Start-Sleep -Seconds 20 }
    }

    if ($wacOnline) {
        Write-Host "  hvwac01 online. Starting WAC vMode install (runs in background) ..."

        # Pull PG password from KV
        $pgPass = az keyvault secret show --vault-name $KVName `
            --subscription $KVSubscription `
            --name 'hvlab-wac-pg-password' --query value -o tsv
        if (-not $pgPass) { $pgPass = 'WACpgAdmin2025!' }  # fallback

        $wacJob = Invoke-Command -ComputerName $wacConfig.Name -Credential $djCred `
            -ArgumentList $pgPass -AsJob -ScriptBlock {
            param($pgPwd)
            $dir = 'C:\WACvmode'
            New-Item -ItemType Directory $dir -Force | Out-Null

            # 1. VC++ Redist prereq
            Write-Host "Installing VC++ Redistributable ..."
            winget install Microsoft.VCRedist.2015+.x64 --Silent `
                --Accept-Package-Agreements --Accept-Source-Agreements 2>&1 | Out-Null

            # 2. Download WAC vMode installer
            Write-Host "Downloading WAC vMode installer ..."
            Invoke-WebRequest -Uri 'https://aka.ms/WACDownloadvMode' `
                -OutFile "$dir\WACvmode.exe" -UseBasicParsing -MaximumRedirection 10

            # 3. Install silently
            Write-Host "Installing WAC vMode (this takes ~10 min) ..."
            $args = "/quiet /L*v $dir\install.log SME_PORT=443 PG_PORT=5432 PG_USERNAME=wacadmin PG_PASSWORD=$pgPwd"
            Start-Process -FilePath "$dir\WACvmode.exe" -ArgumentList $args -Wait -NoNewWindow

            # 4. Firewall
            New-NetFirewallRule -DisplayName 'WAC vMode HTTPS' -Direction Inbound `
                -Protocol TCP -LocalPort 443 -Action Allow -ErrorAction SilentlyContinue | Out-Null

            $svc = Get-Service -Name 'ServerManagementGateway' -ErrorAction SilentlyContinue
            if ($svc) { Write-Host "WAC vMode service: $($svc.Status)" }
            else       { Write-Warning "WAC vMode service not found — check $dir\install.log" }
        }

        Write-OK "WAC vMode install running on hvwac01 (Job ID: $($wacJob.Id)) — check with: Receive-Job $($wacJob.Id)"
        Write-Warn "WAC install takes ~10 min. You can proceed with cluster validation while it runs."
    } else {
        Write-Warn "hvwac01 did not come back online in time. Run configure/04-configure-wac-vmode.ps1 manually."
    }
}

#─────────────────────────────────────────────────────────────────────────────
# SUMMARY
#─────────────────────────────────────────────────────────────────────────────
$elapsed = [int]((Get-Date) - $startTime).TotalMinutes
Write-Host @"

╔══════════════════════════════════════════════════════════════════════════╗
║              EMERGENCY CLUSTER DEPLOY — COMPLETE ($elapsed min elapsed)
╠══════════════════════════════════════════════════════════════════════════╣
║  Cluster : $ClusterName ($ClusterIP)
║  Nodes   : hvnode01, hvnode02, hvnode03, hvnode04
║  Witness : Cloud ($WitnessStorage)
║  CSVs    : CSV01-Data, CSV02-Data, CSV03-Templates
║  WAC URL : https://$($wacConfig.ExternalIP)  (hvwac01 — install may still be running)
╠══════════════════════════════════════════════════════════════════════════╣
║  NEXT STEPS:
║  1. Verify cluster:   Get-ClusterNode -Cluster $ClusterName
║  2. Verify CSVs:      Get-ClusterSharedVolume -Cluster $ClusterName
║  3. Check WAC job:    Receive-Job <JobId>   (from above output)
║  4. SCVMM install:    run configure/06-configure-scvmm.ps1
║  5. Take checkpoint:  run demo/01-take-checkpoint.ps1
╚══════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green
