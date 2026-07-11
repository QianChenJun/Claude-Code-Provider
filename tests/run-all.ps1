#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Run all PowerShell and Node syntax checks for AI CLI Switcher.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $repoRoot

$failed = @()
$scripts = @(
    'tests\core-function-tests.ps1',
    'tests\setup-tests.ps1',
    'tests\server-path-tests.ps1',
    'tests\profile-transfer-tests.ps1',
    'tests\install-dryrun-tests.ps1',
    'tests\install-bootstrap-tests.ps1'
)

foreach ($rel in $scripts) {
    $path = Join-Path $repoRoot $rel
    Write-Host ""
    Write-Host "==> $rel"
    try {
        & pwsh -NoProfile -File $path
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "exit code $LASTEXITCODE"
        }
    }
    catch {
        $failed += $rel
        Write-Warning "FAILED: $rel — $($_.Exception.Message)"
    }
}

$nodeFiles = @(
    'src\server.mjs',
    'src\web\app.js'
)
foreach ($rel in $nodeFiles) {
    Write-Host ""
    Write-Host "==> node --check $rel"
    try {
        & node --check (Join-Path $repoRoot $rel)
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "exit code $LASTEXITCODE"
        }
    }
    catch {
        $failed += $rel
        Write-Warning "FAILED: $rel — $($_.Exception.Message)"
    }
}

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Error ("run-all failed: " + ($failed -join ', '))
    exit 1
}

Write-Output 'run-all: PASS'
exit 0
