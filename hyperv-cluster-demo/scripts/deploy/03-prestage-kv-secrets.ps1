##############################################################################
# 03-prestage-kv-secrets.ps1
# Pre-stage all required secrets in kv-tplabs-platform BEFORE deployment.
# Run this interactively — it will prompt for each secret value.
#
# Prerequisites:
#   az login --tenant a9b67171-3fbb-45bf-8394-eb56d02a86e4
#   You need Key Vault Secrets Officer role on kv-tplabs-platform
#
# For GitHub runner token: generate at
#   https://github.com/thisismydemo/mms_2026_hybrid_demo/settings/actions/runners/new
#   (token expires after 1 hour — generate just before running workflow 02)
##############################################################################

param(
    [string]$VaultName = 'kv-tplabs-platform',
    [switch]$CheckOnly  # Just verify which secrets exist, don't set values
)

$ErrorActionPreference = 'Stop'

$requiredSecrets = @(
    @{ Name = 'hvlab-host01-admin-password';   Description = 'Host VM local admin password (complex, 12+ chars)' },
    @{ Name = 'hvlab-github-runner-token';     Description = 'GitHub Actions runner registration token (1-hour expiry — generate last)' },
    @{ Name = 'hvwac01-pg-password';           Description = 'WAC vmode PostgreSQL password' },
    @{ Name = 'svc-hvlab-deploy-password';     Description = 'svc-hvlab-deploy AD service account password' },
    @{ Name = 'svc-scvmm-svc-password';        Description = 'svc-scvmm-svc AD service account password' },
    @{ Name = 'svc-scvmm-agent-password';      Description = 'svc-scvmm-agent AD service account password' },
    @{ Name = 'svc-scvmm-runas-password';      Description = 'svc-scvmm-runas AD service account password' },
    @{ Name = 'svc-sql-scvmm-password';        Description = 'svc-sql-scvmm SQL Server service account password' },
    @{ Name = 'svc-wac-gateway-password';      Description = 'svc-wac-gateway WAC vmode service account password' }
)

Write-Host "`n=== HV-Lab Key Vault Secret Pre-Stage ===" -ForegroundColor Cyan
Write-Host "Vault: $VaultName`n"

$existingSecrets = az keyvault secret list --vault-name $VaultName --output json |
    ConvertFrom-Json | Select-Object -ExpandProperty name

$missing  = @()
$existing = @()

foreach ($secret in $requiredSecrets) {
    if ($existingSecrets -contains $secret.Name) {
        $existing += $secret
        Write-Host "  ✅ $($secret.Name)" -ForegroundColor Green
    } else {
        $missing += $secret
        Write-Host "  ❌ $($secret.Name) — MISSING" -ForegroundColor Red
    }
}

Write-Host "`n$($existing.Count)/$($requiredSecrets.Count) secrets already exist."

if ($CheckOnly -or $missing.Count -eq 0) {
    if ($missing.Count -eq 0) { Write-Host "`n✅ All secrets present. Ready to deploy." -ForegroundColor Green }
    exit 0
}

Write-Host "`nSetting missing secrets interactively..." -ForegroundColor Yellow

foreach ($secret in $missing) {
    Write-Host "`n$($secret.Name)" -ForegroundColor Cyan
    Write-Host "  $($secret.Description)"
    $value = Read-Host "  Enter value (input hidden)" -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($value))

    az keyvault secret set `
        --vault-name $VaultName `
        --name $secret.Name `
        --value $plain `
        --output none

    Write-Host "  ✅ Set." -ForegroundColor Green
    $plain = $null
}

Write-Host "`n✅ All secrets staged. Ready to run deployment workflows." -ForegroundColor Green
Write-Host "   ⚠️  Remember: hvlab-github-runner-token expires in 1 hour." -ForegroundColor Yellow
Write-Host "       Re-run this script with just that secret right before workflow 02." -ForegroundColor Yellow
