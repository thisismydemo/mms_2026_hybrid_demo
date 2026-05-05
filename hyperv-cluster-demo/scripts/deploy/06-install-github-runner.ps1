##############################################################################
# 06-install-github-runner.ps1
# Install the GitHub Actions self-hosted runner as a Windows service.
# Run via: az vm run-command invoke (from workflow 02, step "Install Runner")
# Parameters: RunnerToken (from Key Vault, passed by workflow)
#
# Runner label: hvlab-host
# Workflows 03-08 target: runs-on: [self-hosted, hvlab-host]
##############################################################################

param(
    [Parameter(Mandatory)]
    [string]$RunnerToken,
    [string]$GitHubOrg        = 'thisismydemo',
    [string]$GitHubRepo       = 'mms_2026_hybrid_demo',
    [string]$RunnerLabel      = 'hvlab-host',
    [string]$RunnerName       = 'hvlab-host01',
    [string]$InstallDir       = 'C:\actions-runner',
    [string]$RunnerVersion    = '2.319.1'   # Update to latest: https://github.com/actions/runner/releases
)

$ErrorActionPreference = 'Stop'
$logFile = 'C:\hvlab-runner-install.log'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $logFile -Value $line
    Write-Host $line
}

Write-Log "=== GitHub Actions Runner Install ==="
Write-Log "Repo: $GitHubOrg/$GitHubRepo | Label: $RunnerLabel"

# Create install directory
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# Download runner
$runnerUrl = "https://github.com/actions/runner/releases/download/v$RunnerVersion/actions-runner-win-x64-$RunnerVersion.zip"
$zipPath   = "$InstallDir\actions-runner.zip"

Write-Log "Downloading runner v$RunnerVersion..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $runnerUrl -OutFile $zipPath -UseBasicParsing

Write-Log "Extracting..."
Expand-Archive -Path $zipPath -DestinationPath $InstallDir -Force
Remove-Item $zipPath -Force

# Configure runner
Write-Log "Configuring runner..."
Set-Location $InstallDir

$repoUrl = "https://github.com/$GitHubOrg/$GitHubRepo"
$configArgs = @(
    '--url', $repoUrl,
    '--token', $RunnerToken,
    '--name', $RunnerName,
    '--labels', $RunnerLabel,
    '--work', '_work',
    '--unattended',
    '--replace'
)

& "$InstallDir\config.cmd" @configArgs
if ($LASTEXITCODE -ne 0) {
    Write-Log "Runner configuration failed (exit code $LASTEXITCODE)." 'ERROR'
    exit 1
}
Write-Log "Runner configured successfully."

# Install as Windows service (runs as SYSTEM)
Write-Log "Installing runner as Windows service..."
& "$InstallDir\svc.cmd" install
& "$InstallDir\svc.cmd" start

$svc = Get-Service -Name 'actions.runner.*' -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Write-Log "✅ Runner service is running: $($svc.Name)"
} else {
    Write-Log "⚠️  Runner service may not be running. Check: Get-Service 'actions.runner.*'" 'WARN'
}

Write-Log "=== Runner Install Complete ==="
Write-Log "Runner '$RunnerName' registered to $repoUrl with label '$RunnerLabel'"
Write-Log "Workflows using 'runs-on: [self-hosted, hvlab-host]' will now execute on this VM."
