#!/usr/bin/env pwsh
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("provider-install-dryrun-tests-" + [guid]::NewGuid().ToString('N'))
$originalUserProfile = $env:USERPROFILE

function Get-UserPathSnapshot {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if (-not $key) {
        return [pscustomobject]@{
            Exists = $false
            Value  = $null
            Kind   = $null
        }
    }

    try {
        $exists = $key.GetValueNames() -contains 'Path'
        return [pscustomobject]@{
            Exists = $exists
            Value  = if ($exists) {
                # CI 的用户 PATH 可能是 ExpandString，读取原始值可避免 USERPROFILE 变化造成误判。
                $key.GetValue(
                    'Path',
                    $null,
                    [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
                )
            } else {
                $null
            }
            Kind   = if ($exists) { $key.GetValueKind('Path') } else { $null }
        }
    }
    finally {
        $key.Dispose()
    }
}

function Test-UserPathSnapshotEqual {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual
    )

    if ($Expected.Exists -ne $Actual.Exists) { return $false }
    if (-not $Expected.Exists) { return $true }

    return $Expected.Kind -eq $Actual.Kind -and
        [string]::Equals(
            [string]$Expected.Value,
            [string]$Actual.Value,
            [System.StringComparison]::Ordinal
        )
}

function Restore-UserPathSnapshot {
    param([Parameter(Mandatory)]$Snapshot)

    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try {
        if ($Snapshot.Exists) {
            $key.SetValue('Path', $Snapshot.Value, $Snapshot.Kind)
        } else {
            $key.DeleteValue('Path', $false)
        }
    }
    finally {
        $key.Dispose()
    }
}

$originalUserPath = Get-UserPathSnapshot

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
        -Condition (Test-UserPathSnapshotEqual -Expected $originalUserPath -Actual (Get-UserPathSnapshot)) `
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
    $currentUserPath = Get-UserPathSnapshot
    if (-not (Test-UserPathSnapshotEqual -Expected $originalUserPath -Actual $currentUserPath)) {
        Restore-UserPathSnapshot -Snapshot $originalUserPath
    }
    Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}
