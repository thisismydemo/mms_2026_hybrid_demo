[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,
    [string]$SubscriptionId = '00cd4357-ed45-4efb-bee0-10c467ff994b',
    [string]$ResourceGroup = 'rg-hvlab-mms26-eus-01',
    [string]$Location = 'eastus',
    [string]$VmSize = 'Standard_M32ms',
    [switch]$SkipArmValidation,
    [switch]$IncludeAnalyzerWarnings,
    [switch]$FailOnAnalyzerWarnings
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hypervRoot = Join-Path $RepoRoot 'hyperv-cluster-demo'
$bicepRoot = Join-Path $hypervRoot 'bicep'
$mainTemplate = Join-Path $bicepRoot 'main.bicep'
$identityTemplate = Join-Path $bicepRoot 'identity.bicep'
$paramsFile = Join-Path $bicepRoot 'parameters\tplabs.bicepparam'
$tempRoot = Join-Path $env:TEMP ('hvlab-preflight-' + [guid]::NewGuid().ToString('N'))

function Write-Section {
    param([string]$Title)

    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
}

function New-SummaryRow {
    param(
        [string]$Check,
        [string]$Result,
        [string]$Details
    )

    [PSCustomObject]@{
        Check = $Check
        Result = $Result
        Details = $Details
    }
}

function Assert-AzCommandSucceeded {
    param(
        [int]$ExitCode,
        [string[]]$Output,
        [string]$Context
    )

    if ($ExitCode -ne 0) {
        $message = ($Output | Out-String).Trim()
        throw "$Context failed. $message"
    }
}

function Get-AzTerminalValue {
    param([string[]]$Output)

    $text = ($Output | Out-String).Trim()
    if (-not $text) {
        return ''
    }

    $stateMatch = [regex]::Match($text, '\b(Succeeded|Failed|Canceled|Accepted|Running)\b\s*$')
    if ($stateMatch.Success) {
        return $stateMatch.Groups[1].Value
    }

    $lines = @(
        $text -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object {
                $_ -and
                $_ -notmatch '^WARNING:'
            }
    )

    if ($lines.Count -eq 0) {
        return ''
    }

    return $lines[-1]
}

$summaryRows = New-Object System.Collections.Generic.List[object]

New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    Write-Section 'PowerShell parser validation'
    $psFiles = Get-ChildItem -Path $RepoRoot -Recurse -Include *.ps1,*.psm1 -File
    $parseFailures = New-Object System.Collections.Generic.List[object]
    foreach ($file in $psFiles) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors) {
            foreach ($parseIssue in $parseErrors) {
                $parseFailures.Add([PSCustomObject]@{
                    File = $file.FullName
                    Line = $parseIssue.Extent.StartLineNumber
                    Column = $parseIssue.Extent.StartColumnNumber
                    Message = $parseIssue.Message
                })
            }
        }
    }

    if ($parseFailures.Count -gt 0) {
        $parseFailures | Sort-Object File, Line | Format-Table -AutoSize | Out-String | Write-Host
        throw "PowerShell parser validation failed for $($parseFailures.Count) issue(s)."
    }

    Write-Host "Validated $($psFiles.Count) PowerShell files."
    $summaryRows.Add((New-SummaryRow -Check 'PowerShell Parse' -Result 'Passed' -Details "$($psFiles.Count) files"))

    Write-Section 'PSScriptAnalyzer validation'
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        throw 'PSScriptAnalyzer is not installed. Install it before running preflight validation.'
    }

    $analyzerErrors = @(Invoke-ScriptAnalyzer -Path $hypervRoot -Recurse -Severity Error)
    $analyzerWarnings = @()

    if ($analyzerErrors.Count -gt 0) {
        $analyzerErrors |
            Select-Object RuleName, ScriptName, Line, Message |
            Sort-Object ScriptName, Line |
            Format-Table -AutoSize |
            Out-String |
            Write-Host
        throw "PSScriptAnalyzer found $($analyzerErrors.Count) error(s)."
    }

    if ($IncludeAnalyzerWarnings -or $FailOnAnalyzerWarnings) {
        $analyzerWarnings = @(Invoke-ScriptAnalyzer -Path $hypervRoot -Recurse -Severity Warning)
    }

    if ($FailOnAnalyzerWarnings -and $analyzerWarnings.Count -gt 0) {
        $analyzerWarnings |
            Select-Object RuleName, ScriptName, Line, Message |
            Sort-Object ScriptName, Line |
            Format-Table -AutoSize |
            Out-String |
            Write-Host
        throw "PSScriptAnalyzer found $($analyzerWarnings.Count) warning(s) and FailOnAnalyzerWarnings was specified."
    }

    if ($IncludeAnalyzerWarnings -and $analyzerWarnings.Count -gt 0) {
        Write-Host "Analyzer warnings: $($analyzerWarnings.Count)" -ForegroundColor Yellow
        $topWarnings = $analyzerWarnings |
            Group-Object RuleName |
            Sort-Object Count -Descending |
            Select-Object -First 10 @{ Name = 'RuleName'; Expression = { $_.Name } }, Count
        $topWarnings | Format-Table -AutoSize | Out-String | Write-Host
        $summaryRows.Add((New-SummaryRow -Check 'PSScriptAnalyzer' -Result 'Passed with warnings' -Details "$($analyzerWarnings.Count) warnings, 0 errors"))
    } elseif ($IncludeAnalyzerWarnings) {
        Write-Host 'Analyzer warnings: 0'
        $summaryRows.Add((New-SummaryRow -Check 'PSScriptAnalyzer' -Result 'Passed' -Details '0 warnings, 0 errors'))
    } else {
        Write-Host 'Analyzer warnings: skipped (use -IncludeAnalyzerWarnings to enumerate them)'
        $summaryRows.Add((New-SummaryRow -Check 'PSScriptAnalyzer' -Result 'Passed' -Details '0 errors; warnings not enumerated'))
    }

    Write-Section 'Bicep compilation validation'
    $bicepFiles = Get-ChildItem -Path $bicepRoot -Recurse -Filter *.bicep -File
    $buildFailures = New-Object System.Collections.Generic.List[object]
    foreach ($file in $bicepFiles) {
        $outFile = Join-Path $tempRoot ($file.BaseName + '.json')
        $buildOutput = & az bicep build --file $file.FullName --outfile $outFile 2>&1
        if ($LASTEXITCODE -ne 0) {
            $buildFailures.Add([PSCustomObject]@{
                File = $file.FullName
                Output = ($buildOutput | Out-String).Trim()
            })
        }
    }

    $compiledParamsFile = Join-Path $tempRoot 'tplabs.parameters.json'
    $paramsBuildOutput = & az bicep build-params --file $paramsFile --outfile $compiledParamsFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        $buildFailures.Add([PSCustomObject]@{
            File = $paramsFile
            Output = ($paramsBuildOutput | Out-String).Trim()
        })
    }

    if ($buildFailures.Count -gt 0) {
        $buildFailures | Format-List | Out-String | Write-Host
        throw "Bicep compilation failed for $($buildFailures.Count) file(s)."
    }

    Write-Host "Compiled $($bicepFiles.Count) Bicep templates and 1 parameter file."
    $summaryRows.Add((New-SummaryRow -Check 'Bicep Build' -Result 'Passed' -Details "$($bicepFiles.Count) templates, 1 parameter file"))

    if ($SkipArmValidation) {
        $summaryRows.Add((New-SummaryRow -Check 'ARM Validate' -Result 'Skipped' -Details 'SkipArmValidation specified'))
    } else {
        Write-Section 'ARM template validation'
        $accountOutput = & az account show --subscription $SubscriptionId --query '{id:id, name:name}' -o json 2>&1
        Assert-AzCommandSucceeded -ExitCode $LASTEXITCODE -Output $accountOutput -Context 'Azure account check'

        $mainValidateOutput = & az deployment group validate `
            --subscription $SubscriptionId `
            --resource-group $ResourceGroup `
            --template-file $mainTemplate `
            --parameters $paramsFile `
            --parameters location=$Location vmSize=$VmSize `
            --only-show-errors `
            --query properties.provisioningState -o tsv 2>&1
        Assert-AzCommandSucceeded -ExitCode $LASTEXITCODE -Output $mainValidateOutput -Context 'main.bicep ARM validation'
        $mainProvisioningState = Get-AzTerminalValue -Output $mainValidateOutput
        if ($mainProvisioningState -ne 'Succeeded') {
            throw "main.bicep ARM validation returned '$mainProvisioningState'."
        }

        $identityValidateOutput = & az deployment sub validate `
            --subscription $SubscriptionId `
            --location $Location `
            --template-file $identityTemplate `
            --parameters location=$Location `
            --only-show-errors `
            --query properties.provisioningState -o tsv 2>&1
        Assert-AzCommandSucceeded -ExitCode $LASTEXITCODE -Output $identityValidateOutput -Context 'identity.bicep ARM validation'
        $identityProvisioningState = Get-AzTerminalValue -Output $identityValidateOutput
        if ($identityProvisioningState -ne 'Succeeded') {
            throw "identity.bicep ARM validation returned '$identityProvisioningState'."
        }

        Write-Host 'ARM validation passed for main.bicep and identity.bicep.'
        $summaryRows.Add((New-SummaryRow -Check 'ARM Validate' -Result 'Passed' -Details 'main.bicep and identity.bicep'))
    }

    Write-Section 'Validation summary'
    $summaryRows | Format-Table -AutoSize | Out-String | Write-Host

    if ($env:GITHUB_STEP_SUMMARY) {
        '## HVLab Preflight Validation' | Out-File $env:GITHUB_STEP_SUMMARY -Append
        '' | Out-File $env:GITHUB_STEP_SUMMARY -Append
        '| Check | Result | Details |' | Out-File $env:GITHUB_STEP_SUMMARY -Append
        '|---|---|---|' | Out-File $env:GITHUB_STEP_SUMMARY -Append
        foreach ($row in $summaryRows) {
            "| $($row.Check) | $($row.Result) | $($row.Details) |" | Out-File $env:GITHUB_STEP_SUMMARY -Append
        }
    }
}
finally {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}