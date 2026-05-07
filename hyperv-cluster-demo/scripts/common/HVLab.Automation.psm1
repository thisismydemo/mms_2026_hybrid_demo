Set-StrictMode -Version Latest

$script:HvLabDefaultKvName = 'kv-tplabs-platform'
$script:HvLabDefaultKvSubscription = '2caa0b8a-a1d6-4f0c-8c03-861787b8315c'

function Get-HVLabStorageRoot {
    [CmdletBinding()]
    param(
        [string]$PreferredRoot
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    if ($PreferredRoot) {
        $candidates.Add($PreferredRoot.TrimEnd('\'))
    }

    $storageVolume = Get-Volume -FileSystemLabel 'HyperVStorage' -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveLetter } |
        Select-Object -First 1
    if ($storageVolume) {
        $candidates.Add("$($storageVolume.DriveLetter):\HyperVStorage")
    }

    foreach ($path in @(
        'D:\HyperVStorage',
        'F:\HyperVStorage',
        'E:\HyperVStorage',
        'C:\HyperVStorage'
    )) {
        $candidates.Add($path)
    }

    $vmHost = Get-VMHost -ErrorAction SilentlyContinue
    if ($vmHost -and $vmHost.VirtualMachinePath) {
        $vmRoot = Split-Path -Path $vmHost.VirtualMachinePath -Parent
        if ($vmRoot) {
            $candidates.Add($vmRoot.TrimEnd('\'))
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return 'D:\HyperVStorage'
}

function Resolve-HVLabStoragePath {
    [CmdletBinding()]
    param(
        [string]$StorageRoot,
        [Parameter(Mandatory)]
        [string]$ChildPath
    )

    $root = Get-HVLabStorageRoot -PreferredRoot $StorageRoot
    return (Join-Path $root $ChildPath)
}

function Get-HVLabSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SecretName,
        [string]$VaultName = $script:HvLabDefaultKvName,
        [string]$SubscriptionId = $script:HvLabDefaultKvSubscription
    )

    $value = az keyvault secret show `
        --vault-name $VaultName `
        --subscription $SubscriptionId `
        --name $SecretName `
        --query value -o tsv

    if (-not $value) {
        throw "Unable to resolve Key Vault secret '$SecretName' from '$VaultName'."
    }

    return $value
}

function New-HVLabBootstrapCredential {
    [CmdletBinding()]
    param(
        [string]$SecretValue,
        [string]$AccountName = 'Administrator',
        [string]$VaultName = $script:HvLabDefaultKvName,
        [string]$SubscriptionId = $script:HvLabDefaultKvSubscription,
        [string]$SecretName = 'hvlab-host01-admin-password'
    )

    if (-not $SecretValue) {
        $SecretValue = Get-HVLabSecret -SecretName $SecretName -VaultName $VaultName -SubscriptionId $SubscriptionId
    }

    $securePassword = New-Object System.Security.SecureString
    foreach ($character in $SecretValue.ToCharArray()) {
        $securePassword.AppendChar($character)
    }
    $securePassword.MakeReadOnly()

    return New-Object System.Management.Automation.PSCredential($AccountName, $securePassword)
}

function Get-HVLabHostDnsServers {
    [CmdletBinding()]
    param()

    $configs = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ServerAddresses -and
            $_.InterfaceAlias -notlike 'vEthernet*' -and
            $_.InterfaceAlias -notlike 'Loopback*'
        }

    foreach ($config in $configs) {
        if ($config.ServerAddresses.Count -gt 0) {
            return @($config.ServerAddresses)
        }
    }

    return @('168.63.129.16')
}

function Get-HVLabWindowsImageIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ImagePath,
        [string]$ImageName,
        [uint32]$ImageIndex
    )

    if ($ImageIndex) {
        return $ImageIndex
    }

    $images = Get-WindowsImage -ImagePath $ImagePath
    if ($ImageName) {
        $matched = $images | Where-Object { $_.ImageName -eq $ImageName -or $_.ImageDescription -eq $ImageName } | Select-Object -First 1
        if ($matched) {
            return [uint32]$matched.ImageIndex
        }
        throw "Unable to find image '$ImageName' in '$ImagePath'."
    }

    return [uint32](($images | Select-Object -First 1).ImageIndex)
}

function New-HVLabOfflineUnattendXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [Parameter(Mandatory)]
        [string]$AdminPassword
    )

    return @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <ComputerName>$ComputerName</ComputerName>
      <TimeZone>UTC</TimeZone>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <AutoLogon>
        <Password>
          <Value>$AdminPassword</Value>
          <PlainText>true</PlainText>
        </Password>
        <Enabled>true</Enabled>
        <LogonCount>1</LogonCount>
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
      <UserAccounts>
        <AdministratorPassword>
          <Value>$AdminPassword</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Description>HVLab first boot baseline</Description>
          <CommandLine>powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\HVLab-FirstBoot.ps1</CommandLine>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
"@
}

function New-HVLabFirstBootScript {
    [CmdletBinding()]
    param()

    return @"
















New-Item -Path C:\Temp -ItemType Directory -Force | Out-Null
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Service\Auth\Basic -Value `$true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value `$true
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name LocalAccountTokenFilterPolicy -PropertyType DWord -Value 1 -Force | Out-Null
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
Enable-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue
Get-NetConnectionProfile -ErrorAction SilentlyContinue | ForEach-Object {
    Set-NetConnectionProfile -InterfaceIndex `$_.InterfaceIndex -NetworkCategory Private -ErrorAction SilentlyContinue
}
Restart-Service -Name vmicvmsession -ErrorAction SilentlyContinue
"@
}

function New-HVLabWindowsVhd {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IsoPath,
        [Parameter(Mandatory)]
        [string]$VhdPath,
        [Parameter(Mandatory)]
        [int]$SizeGB,
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [Parameter(Mandatory)]
        [string]$AdminPassword,
        [string]$ImageName,
        [uint32]$ImageIndex,
        [switch]$Force
    )

    if ((Test-Path $VhdPath) -and -not $Force) {
        return $VhdPath
    }

    if (-not (Test-Path $IsoPath)) {
        throw "ISO path '$IsoPath' not found."
    }

    $vhdDirectory = Split-Path -Path $VhdPath -Parent
    New-Item -Path $vhdDirectory -ItemType Directory -Force | Out-Null

    if (Test-Path $VhdPath) {
        Remove-Item -Path $VhdPath -Force
    }

    $iso = Mount-DiskImage -ImagePath $IsoPath -PassThru
    try {
        $isoVolume = $iso | Get-Volume
        $imagePath = @(
            (Join-Path "$($isoVolume.DriveLetter):\sources" 'install.wim'),
            (Join-Path "$($isoVolume.DriveLetter):\sources" 'install.esd')
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $imagePath) {
            throw "Unable to find install.wim or install.esd in '$IsoPath'."
        }

        $resolvedIndex = Get-HVLabWindowsImageIndex -ImagePath $imagePath -ImageName $ImageName -ImageIndex $ImageIndex

        New-VHD -Path $VhdPath -SizeBytes ($SizeGB * 1GB) -Dynamic | Out-Null
        $mountedVhd = Mount-VHD -Path $VhdPath -PassThru

        try {
            $disk = $mountedVhd | Get-Disk
            Initialize-Disk -Number $disk.Number -PartitionStyle GPT | Out-Null

            $efiPartition = New-Partition -DiskNumber $disk.Number -Size 260MB -AssignDriveLetter -GptType '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}'
            Format-Volume -Partition $efiPartition -FileSystem FAT32 -NewFileSystemLabel 'System' -Confirm:$false | Out-Null

            New-Partition -DiskNumber $disk.Number -Size 16MB -GptType '{E3C9E316-0B5C-4DB8-817D-F92DF00215AE}' | Out-Null

            $osPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
            Format-Volume -Partition $osPartition -FileSystem NTFS -NewFileSystemLabel 'Windows' -Confirm:$false | Out-Null

            $efiDrive = ($efiPartition | Get-Volume).DriveLetter
            $osDrive = ($osPartition | Get-Volume).DriveLetter

            $dismLog = Join-Path $env:TEMP 'hvlab-expand-image.log'
            if ($imagePath -like '*.wim') {
                Expand-WindowsImage -ImagePath $imagePath -Index $resolvedIndex -ApplyPath "$osDrive`:" -CheckIntegrity -Verify -LogPath $dismLog | Out-Null
            } else {
                & dism.exe /Apply-Image /ImageFile:$imagePath /Index:$resolvedIndex /ApplyDir:"$osDrive`:\" /CheckIntegrity | Out-Null
            }

            $pantherPath = Join-Path "$osDrive`:" 'Windows\Panther'
            $setupScriptsPath = Join-Path "$osDrive`:" 'Windows\Setup\Scripts'
            New-Item -Path $pantherPath -ItemType Directory -Force | Out-Null
            New-Item -Path $setupScriptsPath -ItemType Directory -Force | Out-Null

            New-HVLabOfflineUnattendXml -ComputerName $ComputerName -AdminPassword $AdminPassword |
                Set-Content -Path (Join-Path $pantherPath 'Unattend.xml') -Encoding UTF8

            New-HVLabFirstBootScript |
                Set-Content -Path (Join-Path $setupScriptsPath 'HVLab-FirstBoot.ps1') -Encoding UTF8

            @(
                '@echo off',
                'powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\HVLab-FirstBoot.ps1'
            ) | Set-Content -Path (Join-Path $setupScriptsPath 'SetupComplete.cmd') -Encoding ASCII

            & bcdboot.exe "$osDrive`:\Windows" /s "$efiDrive`:" /f UEFI | Out-Null
        }
        finally {
            Dismount-VHD -Path $VhdPath -ErrorAction SilentlyContinue
        }
    }
    finally {
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
    }

    return $VhdPath
}

function New-HVLabVm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$OSVhdPath,
        [Parameter(Mandatory)]
        [string]$VmPath,
        [Parameter(Mandatory)]
        [int]$MemoryGB,
        [Parameter(Mandatory)]
        [int]$ProcessorCount,
        [Parameter(Mandatory)]
        [array]$AdapterDefinitions,
        [string[]]$DataVhdPaths,
        [switch]$ExposeVirtualizationExtensions,
        [switch]$ForceRecreate
    )

    $existingVm = Get-VM -Name $Name -ErrorAction SilentlyContinue
    if ($existingVm -and $ForceRecreate) {
        if ($existingVm.State -ne 'Off') {
            Stop-VM -Name $Name -Force -TurnOff -ErrorAction SilentlyContinue
        }
        Remove-VM -Name $Name -Force
        $existingVm = $null
    }

    if (-not $existingVm) {
        if (-not $AdapterDefinitions -or $AdapterDefinitions.Count -eq 0) {
            throw 'At least one adapter definition is required.'
        }

        New-Item -Path $VmPath -ItemType Directory -Force | Out-Null
        $primaryAdapter = $AdapterDefinitions[0]
        $vm = New-VM -Name $Name -Generation 2 -MemoryStartupBytes ($MemoryGB * 1GB) -VHDPath $OSVhdPath -Path $VmPath -SwitchName $primaryAdapter.SwitchName
        Rename-VMNetworkAdapter -VMName $Name -Name 'Network Adapter' -NewName $primaryAdapter.Name

        for ($i = 1; $i -lt $AdapterDefinitions.Count; $i++) {
            $adapter = $AdapterDefinitions[$i]
            Add-VMNetworkAdapter -VMName $Name -Name $adapter.Name -SwitchName $adapter.SwitchName | Out-Null
        }

        if ($DataVhdPaths) {
            foreach ($dataVhdPath in $DataVhdPaths) {
                Add-VMHardDiskDrive -VMName $Name -Path $dataVhdPath | Out-Null
            }
        }
    } else {
        $vm = $existingVm
    }

    Set-VMMemory -VMName $Name -DynamicMemoryEnabled $false | Out-Null
    Set-VMProcessor -VMName $Name -Count $ProcessorCount -ExposeVirtualizationExtensions:$ExposeVirtualizationExtensions.IsPresent | Out-Null
    Set-VMFirmware -VMName $Name -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows | Out-Null

    foreach ($adapterDefinition in $AdapterDefinitions) {
        $vmAdapter = Get-VMNetworkAdapter -VMName $Name -Name $adapterDefinition.Name -ErrorAction Stop
        Set-VMNetworkAdapter -VMNetworkAdapter $vmAdapter -DeviceNaming On | Out-Null

        if ($adapterDefinition.ContainsKey('EnableMacAddressSpoofing') -and $adapterDefinition.EnableMacAddressSpoofing) {
            Set-VMNetworkAdapter -VMNetworkAdapter $vmAdapter -MacAddressSpoofing On | Out-Null
        }

        if ($adapterDefinition.ContainsKey('StaticMacAddress') -and $adapterDefinition.StaticMacAddress) {
            Set-VMNetworkAdapter -VMNetworkAdapter $vmAdapter -StaticMacAddress $adapterDefinition.StaticMacAddress | Out-Null
        }
    }

    $osDrive = Get-VMHardDiskDrive -VMName $Name | Where-Object { $_.Path -eq $OSVhdPath } | Select-Object -First 1
    if ($osDrive) {
        Set-VMFirmware -VMName $Name -FirstBootDevice $osDrive | Out-Null
    }

    if ((Get-VM -Name $Name).State -ne 'Running') {
        Start-VM -Name $Name | Out-Null
    }

    return (Get-VM -Name $Name)
}

function Wait-HVLabPowerShellDirect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Credential,
        [int]$TimeoutMinutes = 20
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        try {
            $result = Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop
            if ($result) {
                return $true
            }
        }
        catch {
        }

        Start-Sleep -Seconds 15
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for PowerShell Direct on '$VMName'."
}

function Invoke-HVLabPowerShellDirect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList,
        [switch]$Quiet
    )

    Wait-HVLabPowerShellDirect -VMName $VMName -Credential $Credential | Out-Null
    if ($Quiet) {
        return Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop | Out-Null
    }

    return Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
}

function Initialize-HVLabGuestNetwork {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory)]
        [array]$AdapterConfigurations
    )

    $adapterData = @()
    foreach ($adapterConfiguration in $AdapterConfigurations) {
        $vmAdapter = Get-VMNetworkAdapter -VMName $VMName -Name $adapterConfiguration.Name -ErrorAction Stop
        $adapterData += [PSCustomObject]@{
            HostName   = $adapterConfiguration.Name
            GuestName  = $adapterConfiguration.GuestName
            MacAddress = $vmAdapter.MacAddress
            IPAddress  = $adapterConfiguration.IPAddress
            PrefixLength = $adapterConfiguration.PrefixLength
            Gateway    = $adapterConfiguration.Gateway
            DnsServers = $adapterConfiguration.DnsServers
        }
    }

    $json = $adapterData | ConvertTo-Json -Depth 4 -Compress

    Invoke-HVLabPowerShellDirect -VMName $VMName -Credential $Credential -ArgumentList $json -ScriptBlock {
        param($AdapterJson)

        $guestAdapters = Get-NetAdapter | Where-Object { $_.Status -ne 'Disabled' }
        $adapterConfigurations = $AdapterJson | ConvertFrom-Json

        foreach ($adapterConfiguration in $adapterConfigurations) {
            $targetMac = ($adapterConfiguration.MacAddress -replace '[:-]', '').ToUpperInvariant()
            $guestAdapter = $guestAdapters |
                Where-Object { (($_.MacAddress -replace '-', '').ToUpperInvariant()) -eq $targetMac } |
                Select-Object -First 1

            if (-not $guestAdapter) {
                throw "Unable to find guest adapter with MAC '$($adapterConfiguration.MacAddress)'."
            }

            $currentName = $guestAdapter.Name
            if ($currentName -ne $adapterConfiguration.GuestName) {
                Rename-NetAdapter -Name $currentName -NewName $adapterConfiguration.GuestName -ErrorAction Stop | Out-Null
                $currentName = $adapterConfiguration.GuestName
            }

            Set-NetIPInterface -InterfaceAlias $currentName -Dhcp Disabled -ErrorAction SilentlyContinue | Out-Null

            if ($adapterConfiguration.IPAddress) {
                $existing = Get-NetIPAddress -InterfaceAlias $currentName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -eq $adapterConfiguration.IPAddress }
                if (-not $existing) {
                    Get-NetIPAddress -InterfaceAlias $currentName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                        Where-Object { $_.PrefixOrigin -ne 'WellKnown' } |
                        ForEach-Object { Remove-NetIPAddress -InputObject $_ -Confirm:$false -ErrorAction SilentlyContinue }

                    $ipParams = @{
                        InterfaceAlias = $currentName
                        IPAddress      = $adapterConfiguration.IPAddress
                        PrefixLength   = [int]$adapterConfiguration.PrefixLength
                    }
                    if ($adapterConfiguration.Gateway) {
                        $ipParams.DefaultGateway = $adapterConfiguration.Gateway
                    }
                    New-NetIPAddress @ipParams -ErrorAction Stop | Out-Null
                }
            }

            if ($adapterConfiguration.DnsServers) {
                $dnsServers = @($adapterConfiguration.DnsServers)
                Set-DnsClientServerAddress -InterfaceAlias $currentName -ServerAddresses $dnsServers -ErrorAction Stop
            }
        }

        Get-NetConnectionProfile -ErrorAction SilentlyContinue | ForEach-Object {
            Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private -ErrorAction SilentlyContinue
        }

        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
        Enable-PSRemoting -Force
        Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
        Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name LocalAccountTokenFilterPolicy -PropertyType DWord -Value 1 -Force | Out-Null
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
        Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
        Enable-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue
        ipconfig /flushdns | Out-Null
    } | Out-Null
}

function Restart-HVLabGuest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Credential,
        [int]$DelaySeconds = 15,
        [int]$TimeoutMinutes = 20
    )

    Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
        Start-Sleep -Seconds $using:DelaySeconds
        Restart-Computer -Force
    } -ErrorAction SilentlyContinue | Out-Null

    Start-Sleep -Seconds ([Math]::Max($DelaySeconds, 5))
    Wait-HVLabPowerShellDirect -VMName $VMName -Credential $Credential -TimeoutMinutes $TimeoutMinutes | Out-Null
}

function Join-HVLabGuestToDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$LocalCredential,
        [Parameter(Mandatory)]
        [string]$DomainFqdn,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$DomainCredential,
        [string]$OUPath,
        [string[]]$DnsServers,
        [int]$RestartDelaySeconds = 15,
        [int]$TimeoutMinutes = 20
    )

    Invoke-HVLabPowerShellDirect -VMName $VMName -Credential $LocalCredential -ArgumentList $DomainFqdn, $DomainCredential, $OUPath, $DnsServers, $RestartDelaySeconds -ScriptBlock {
        param($DomainFqdn, $DomainCredential, $OUPath, $DnsServers, $RestartDelaySeconds)

        if ($DnsServers) {
            $primaryAdapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Sort-Object InterfaceIndex | Select-Object -First 1
            if ($primaryAdapter) {
                Set-DnsClientServerAddress -InterfaceAlias $primaryAdapter.Name -ServerAddresses $DnsServers -ErrorAction SilentlyContinue
            }
        }

        $currentDomain = (Get-CimInstance Win32_ComputerSystem).Domain
        $alreadyJoined = $false
        if ($currentDomain -eq $DomainFqdn) {
            $alreadyJoined = $true
        }

        if (-not $alreadyJoined) {
            $joinParams = @{
                DomainName = $DomainFqdn
                Credential = $DomainCredential
                Force      = $true
            }
            if ($OUPath) {
                $joinParams.OUPath = $OUPath
            }
            Add-Computer @joinParams
        }

        Start-Sleep -Seconds $RestartDelaySeconds
        Restart-Computer -Force
    } | Out-Null

    Start-Sleep -Seconds ([Math]::Max($RestartDelaySeconds, 5))
    Wait-HVLabPowerShellDirect -VMName $VMName -Credential $LocalCredential -TimeoutMinutes $TimeoutMinutes | Out-Null
}

Export-ModuleMember -Function @(
    'Get-HVLabHostDnsServers',
    'Get-HVLabSecret',
    'Get-HVLabStorageRoot',
    'Initialize-HVLabGuestNetwork',
    'Invoke-HVLabPowerShellDirect',
    'Join-HVLabGuestToDomain',
    'New-HVLabBootstrapCredential',
    'New-HVLabVm',
    'New-HVLabWindowsVhd',
    'Resolve-HVLabStoragePath',
    'Restart-HVLabGuest',
    'Wait-HVLabPowerShellDirect'
)