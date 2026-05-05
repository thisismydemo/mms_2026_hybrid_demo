##############################################################################
# 06-configure-scvmm.ps1  — Install SQL Server Developer + SCVMM 2025
# on hvscvmm01. SQL Developer Edition is FREE for dev/test.
# Run from: self-hosted runner
##############################################################################

param(
    [string]$ScvmmServer       = 'hvscvmm01',
    [string]$SqlISO            = 'D:\HyperVStorage\ISOs\SQL2022Dev.iso',
    [string]$ScvmmSetupDest    = 'D:\HyperVStorage\SCVMM2025',   # downloaded from blob
    [string]$ScvmmStorageAcct  = 'sthvlabcontent01',
    [string]$DomainFqdn        = 'azrl.mgmt',
    [string]$KVName            = 'kv-tplabs-platform',
    [string]$KVSubscription    = '2caa0b8a-a1d6-4f0c-8c03-861787b8315c'
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Installing SQL Server Developer + SCVMM 2025 on $ScvmmServer ===" -ForegroundColor Cyan

# Download SCVMM files from blob storage to host, then copy to nested VM
Write-Host "Downloading SCVMM 2025 installer from blob storage..."
New-Item -ItemType Directory -Path $ScvmmSetupDest -Force | Out-Null
$storageKey = az storage account keys list --account-name $ScvmmStorageAcct `
    --resource-group "rg-hvlab-mms26-eus-01" --query "[0].value" -o tsv
az storage blob download-batch `
    --account-name $ScvmmStorageAcct `
    --source "scvmm" `
    --destination $ScvmmSetupDest `
    --account-key $storageKey | Out-Null
Write-Host "SCVMM installer downloaded to $ScvmmSetupDest"

# Copy SCVMM setup to nested VM
$session = New-PSSession -ComputerName $ScvmmServer
Copy-Item -Path $ScvmmSetupDest -Destination "D:\SCVMM2025" -ToSession $session -Recurse -Force

# Get service account passwords from Key Vault
$sqlSvcPw   = az keyvault secret show --vault-name $KVName --subscription $KVSubscription `
    --name 'hvlab-sqlsa-password' --query value -o tsv
$scvmmSvcPw = az keyvault secret show --vault-name $KVName --subscription $KVSubscription `
    --name 'hvlab-svcaccount-password' --query value -o tsv

Invoke-Command -Session $session -ArgumentList $SqlISO, $DomainFqdn, $sqlSvcPw, $scvmmSvcPw -ScriptBlock {
    param($SqlISO, $DomainFqdn, $SqlSvcPw, $ScvmmSvcPw)
    $ScvmmSetup = 'D:\SCVMM2025\setup.exe'

    # ── SQL Server Developer Edition ─────────────────────────────────────────
    Write-Host "Mounting SQL Server ISO..."
    $sqlDrive = Mount-DiskImage -ImagePath $SqlISO -PassThru | Get-Volume
    $sqlSetup = "$($sqlDrive.DriveLetter):\setup.exe"

    $sqlArgs = @(
        '/Q',
        '/ACTION=Install',
        '/FEATURES=SQLEngine',
        '/INSTANCENAME=MSSQLSERVER',
        "/SQLSVCACCOUNT=AZRL\svc-sql-scvmm",
        "/SQLSVCPASSWORD=$SqlSvcPw",
        '/SQLSYSADMINACCOUNTS=AZRL\Domain Admins',
        '/SQLSVCSTARTUPTYPE=Automatic',
        '/TCPENABLED=1',
        '/NPENABLED=0',
        '/IACCEPTSQLSERVERLICENSETERMS'
    )
    Write-Host "Installing SQL Server Developer..."
    Start-Process -FilePath $sqlSetup -ArgumentList $sqlArgs -Wait -NoNewWindow
    Dismount-DiskImage -ImagePath $SqlISO

    # Verify SQL service
    $sqlSvc = Get-Service -Name MSSQLSERVER
    Write-Host "  SQL Server: $($sqlSvc.Status)"

    # ── SCVMM 2025 ───────────────────────────────────────────────────────────
    Write-Host "Mounting SCVMM 2025 ISO..."
    $scvmmDrive = Mount-DiskImage -ImagePath $ScvmmISO -PassThru | Get-Volume
    $scvmmSetup = "$($scvmmDrive.DriveLetter):\setup.exe"

    # SCVMM silent install — adjust path to match your ISO layout
    $scvmmArgs = @(
        '/server',
        '/i',
        '/IAcceptSCEMLicenseTerms',
        '/SqlDBInstanceName=MSSQLSERVER',
        '/SqlMachineName=hvscvmm01',
        "/ServiceRunAsAccountName=AZRL\svc-scvmm-svc",
        "/ServiceRunAsAccountPassword=$ScvmmSvcPw",
        '/VmmServiceLocalAccount=false',
        '/CreateNewSqlDatabase=1',
        '/SqlInstancePort=1433',
        '/LibraryPath=E:\SCVMMLibrary',
        '/ProductKey='     # blank = use eval/volume license
    )
    Write-Host "Installing SCVMM 2025..."
    Start-Process -FilePath $scvmmSetup -ArgumentList $scvmmArgs -Wait -NoNewWindow
    Dismount-DiskImage -ImagePath $ScvmmISO

    # Verify SCVMM service
    $scvmmSvc = Get-Service -Name SCVMMService -ErrorAction SilentlyContinue
    if ($scvmmSvc) {
        Write-Host "  ✅ SCVMM Service: $($scvmmSvc.Status)"
    } else {
        Write-Warning "SCVMM service not found — check C:\ProgramData\VMMLogs for errors"
    }

    # Create library share
    New-Item -ItemType Directory -Path 'E:\SCVMMLibrary' -Force | Out-Null
    New-SmbShare -Name 'SCVMMLibrary' -Path 'E:\SCVMMLibrary' `
        -FullAccess 'AZRL\Domain Admins','AZRL\svc-scvmm-svc' -ErrorAction SilentlyContinue
    Write-Host "  ✅ SCVMM library share created: \\hvscvmm01\SCVMMLibrary"
}

Write-Host @"

✅ SQL Server Developer + SCVMM 2025 installed on $ScvmmServer.

Next steps (via SCVMM console on hvscvmm01):
  1. Add Hyper-V hosts (hvnode01-04, hviscsi01)
  2. Add cluster hvlab-clus01
  3. Configure logical networks:
     - HVLab-Management  (172.16.10.0/24)
     - HVLab-Workload    (172.16.50.0/24)
  4. Add library server (hvscvmm01 itself)
  5. Create Run As accounts from Key Vault service account passwords

SCVMM console: Open via RDP to 10.250.1.47, launch vmm.exe
"@
