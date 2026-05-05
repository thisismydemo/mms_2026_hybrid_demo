##############################################################################
# 07-configure-dhcp.ps1  — Install DHCP and create scopes on hvdc01
#
# Scopes:
#   Management  172.16.10.0/24  — nested VMs on management network
#   Workload    172.16.50.0/24  — demo workload / tenant VMs
#
# Storage (172.16.30), Migration (172.16.20), Heartbeat (172.16.40):
#   → Static IPs only, no DHCP (cluster traffic must be deterministic)
##############################################################################

param(
    [string]$DHCPServer    = 'hvdc01',
    [string]$DomainFqdn    = 'azrl.mgmt',
    [string]$DomainController = 'hvdc01'
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Configuring DHCP on $DHCPServer ===" -ForegroundColor Cyan

Invoke-Command -ComputerName $DHCPServer -ScriptBlock {
    param($DomainFqdn, $DHCPServer)

    # Install DHCP role
    Install-WindowsFeature -Name DHCP -IncludeManagementTools
    Write-Host "  ✅ DHCP role installed"

    # Authorize in Active Directory
    Add-DhcpServerInDC -DnsName "$DHCPServer.$DomainFqdn" -IPAddress (
        (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '172.16.10.*' }).IPAddress
    )
    Write-Host "  ✅ DHCP server authorized in AD"

    # Suppress post-install security groups warning
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' `
        -Name ConfigurationState -Value 2 -ErrorAction SilentlyContinue

    # ── Management Scope: 172.16.10.0/24 ────────────────────────────────────
    Add-DhcpServerv4Scope `
        -Name         'HVLab Management' `
        -StartRange   '172.16.10.50' `
        -EndRange     '172.16.10.200' `
        -SubnetMask   '255.255.255.0' `
        -Description  'Management network for nested VMs and services' `
        -State        Active

    # Exclusions — reserve static IPs for infrastructure
    Add-DhcpServerv4ExclusionRange -ScopeId '172.16.10.0' -StartRange '172.16.10.1'  -EndRange '172.16.10.49'
    # 172.16.10.1  = vSwitch-Mgmt gateway (host)
    # 172.16.10.10 = hvdc01
    # 172.16.10.15 = hviscsi01 (mgmt)
    # 172.16.10.21-24 = hvnode01-04
    # 172.16.10.30 = hvwac01
    # 172.16.10.40 = hvscvmm01
    # 172.16.10.200 = cluster IP (hvlab-clus01)
    Add-DhcpServerv4ExclusionRange -ScopeId '172.16.10.0' -StartRange '172.16.10.200' -EndRange '172.16.10.250'

    # Scope options
    Set-DhcpServerv4OptionValue -ScopeId '172.16.10.0' `
        -Router    '172.16.10.1' `
        -DnsServer '172.16.10.10' `
        -DnsDomain $DomainFqdn

    Write-Host "  ✅ Management scope 172.16.10.0/24 created (range .50-.199)"

    # ── Workload Scope: 172.16.50.0/24 ──────────────────────────────────────
    Add-DhcpServerv4Scope `
        -Name         'HVLab Workload' `
        -StartRange   '172.16.50.10' `
        -EndRange     '172.16.50.250' `
        -SubnetMask   '255.255.255.0' `
        -Description  'Workload / tenant VMs — demo audience VMs created here' `
        -State        Active

    Set-DhcpServerv4OptionValue -ScopeId '172.16.50.0' `
        -Router    '172.16.50.1' `
        -DnsServer '172.16.10.10' `
        -DnsDomain $DomainFqdn

    Write-Host "  ✅ Workload scope 172.16.50.0/24 created (range .10-.250)"

    # ── DHCP Failover (optional — hvdc01 is single DHCP for now) ────────────
    Write-Host "  ℹ️  DHCP failover not configured (single DC lab — acceptable for demo)"

    # Restart DHCP service to apply
    Restart-Service dhcpserver
    Write-Host "  ✅ DHCP service restarted"

} -ArgumentList $DomainFqdn, $DHCPServer

Write-Host @"

✅ DHCP configured on $DHCPServer.

Scopes:
  Management  172.16.10.50–172.16.10.199   DNS: 172.16.10.10  GW: 172.16.10.1
  Workload    172.16.50.10–172.16.50.250   DNS: 172.16.10.10  GW: 172.16.50.1

Static IPs (excluded/reserved):
  172.16.10.1        vSwitch-Mgmt gateway (host)
  172.16.10.10       hvdc01
  172.16.10.15       hviscsi01
  172.16.10.21–24    hvnode01–04
  172.16.10.30       hvwac01
  172.16.10.40       hvscvmm01
  172.16.10.200      hvlab-clus01 cluster IP
"@
