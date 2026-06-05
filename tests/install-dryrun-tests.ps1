#!/usr/bin/env pwsh
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("provider-install-dryrun-tests-" + [guid]::NewGuid().ToString('N'))
$originalUserProfile = $env:USERPROFILE
$originalUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Force -Path $tempHome | Out-Null
    $env:USERPROFILE = $tempHome

    $installScript = Join-Path $repoRoot 'Claude-Provider-Profiles-Kit\install.ps1'
    $output = & $installScript -DryRun -AddPath -Configure
    $overwriteOutput = & $installScript -DryRun -OverwriteConfig

    Assert-True `
        -Condition (-not (Test-Path -LiteralPath (Join-Path $tempHome '.claude'))) `
        -Message 'DryRun 不应写入 .claude 目录'

    Assert-True `
        -Condition (-not (Test-Path -LiteralPath (Join-Path $tempHome '.codex'))) `
        -Message 'DryRun 不应写入 .codex 目录'

    Assert-True `
        -Condition ([Environment]::GetEnvironmentVariable('Path', 'User') -eq $originalUserPath) `
        -Message 'DryRun 不应修改用户 PATH'

    Assert-True `
        -Condition (($output -join "`n") -match 'DRY-RUN 已跳过配置向导') `
        -Message 'DryRun 搭配 Configure 时不应进入交互配置'

    Assert-True `
        -Condition (($overwriteOutput -join "`n") -match 'DRY-RUN 将覆盖 Claude 配置') `
        -Message 'DryRun 搭配 OverwriteConfig 时应只预告覆盖配置'

    Assert-True `
        -Condition (($output -join "`n") -match 'Manage-ProviderProfiles\.ps1') `
        -Message 'DryRun 应预告部署导入导出工具'

    Write-Output 'install-dryrun-tests: PASS'
}
finally {
    $env:USERPROFILE = $originalUserProfile
    [Environment]::SetEnvironmentVariable('Path', $originalUserPath, 'User')
    Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}
