#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Provider Profiles 配置备份、导入和列表工具。
.DESCRIPTION
    导出 Claude Code / Codex CLI 的 provider 配置，或从备份目录导入配置。
    默认导出会移除 profile 中的明文密钥字段（apiKey/token/key），避免备份包泄露 API Key。
.EXAMPLE
    .\Manage-ProviderProfiles.ps1 export -OutDir "$HOME\Desktop\provider-backup" -Tool all
.EXAMPLE
    .\Manage-ProviderProfiles.ps1 import -InDir "$HOME\Desktop\provider-backup" -Tool codex
.EXAMPLE
    .\Manage-ProviderProfiles.ps1 list -Tool all
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('export', 'import', 'list')]
    [string]$Action,

    [string]$OutDir,

    [string]$InDir,

    [ValidateSet('claude', 'codex', 'all')]
    [string]$Tool = 'all',

    [switch]$Compress,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-UserHomePath {
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($env:HOME) { return $env:HOME }
    throw '无法定位用户目录：USERPROFILE/HOME 未设置'
}

$UserHome = Get-UserHomePath
$SecretFieldNames = @('apiKey', 'token', 'key')
$ToolPaths = @{
    claude = @{
        configPath  = Join-Path $UserHome '.claude\provider-profiles\providers.json'
        displayName = 'Claude Code'
        prefix      = 'ccp'
    }
    codex = @{
        configPath  = Join-Path $UserHome '.codex\provider-profiles\providers.json'
        displayName = 'Codex CLI'
        prefix      = 'cdp'
    }
}

function Write-Utf8NoBomText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )

    Write-Utf8NoBomText -Path $Path -Text (($Value | ConvertTo-Json -Depth 50) + "`n")
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)

    $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "JSON 文件为空：$Path"
    }
    return $text | ConvertFrom-Json
}

function Get-ToolsToProcess {
    param([Parameter(Mandatory)][string]$ToolFilter)

    if ($ToolFilter -eq 'all') { return @('claude', 'codex') }
    return @($ToolFilter)
}

function Test-EnvironmentVariableConfigured {
    param([Parameter(Mandatory)][string]$Name)

    foreach ($target in @('User', 'Process', 'Machine')) {
        if ([Environment]::GetEnvironmentVariable($Name, $target)) {
            return $true
        }
    }
    return $false
}

function Remove-PlaintextSecrets {
    param([Parameter(Mandatory)]$Config)

    $removed = 0
    if (-not $Config.PSObject.Properties['profiles'] -or -not $Config.profiles) {
        return $removed
    }

    foreach ($profileProp in @($Config.profiles.PSObject.Properties)) {
        $profile = $profileProp.Value
        foreach ($fieldName in $SecretFieldNames) {
            $prop = $profile.PSObject.Properties[$fieldName]
            if ($prop) {
                $profile.PSObject.Properties.Remove($prop.Name)
                $removed++
            }
        }
    }
    return $removed
}

function Test-ContainsPlaintextSecrets {
    param([Parameter(Mandatory)]$Config)

    if (-not $Config.PSObject.Properties['profiles'] -or -not $Config.profiles) {
        return $false
    }

    foreach ($profileProp in @($Config.profiles.PSObject.Properties)) {
        foreach ($fieldName in $SecretFieldNames) {
            if ($profileProp.Value.PSObject.Properties[$fieldName]) {
                return $true
            }
        }
    }
    return $false
}

function Get-EnvVarsInfo {
    param([Parameter(Mandatory)]$Config)

    $envVarsInfo = [ordered]@{}
    if (-not $Config.PSObject.Properties['profiles'] -or -not $Config.profiles) {
        return $envVarsInfo
    }

    foreach ($profileProp in @($Config.profiles.PSObject.Properties)) {
        $profile = $profileProp.Value
        foreach ($envField in @('apiKeyEnv', 'tokenEnv', 'keyEnv')) {
            $envProp = $profile.PSObject.Properties[$envField]
            if ($envProp -and $envProp.Value) {
                $envName = "$($envProp.Value)"
                $envVarsInfo[$envName] = [ordered]@{
                    profileId = $profileProp.Name
                    field     = $envField
                    hasValue  = Test-EnvironmentVariableConfigured -Name $envName
                }
            }
        }
    }
    return $envVarsInfo
}

function Resolve-ImportRoot {
    param([Parameter(Mandatory)][string]$Path)

    $root = [System.IO.Path]::GetFullPath($Path)
    $hasToolDirs = (Test-Path -LiteralPath (Join-Path $root 'claude\providers.json')) -or
                   (Test-Path -LiteralPath (Join-Path $root 'codex\providers.json')) -or
                   (Test-Path -LiteralPath (Join-Path $root 'providers.json'))
    if ($hasToolDirs) { return $root }

    $children = @(Get-ChildItem -LiteralPath $root -Directory)
    if ($children.Count -eq 1) {
        $child = $children[0].FullName
        $childHasToolDirs = (Test-Path -LiteralPath (Join-Path $child 'claude\providers.json')) -or
                            (Test-Path -LiteralPath (Join-Path $child 'codex\providers.json')) -or
                            (Test-Path -LiteralPath (Join-Path $child 'providers.json'))
        if ($childHasToolDirs) { return $child }
    }
    return $root
}

function Export-Profiles {
    param(
        [string]$OutDir,
        [string]$ToolFilter,
        [switch]$Compress,
        [switch]$Force
    )

    if (-not $OutDir) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $OutDir = Join-Path $UserHome "Desktop\provider-profiles-backup-$timestamp"
    }

    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    }

    $OutDir = [System.IO.Path]::GetFullPath($OutDir)
    $exported = @()
    $removedSecrets = 0

    foreach ($toolName in (Get-ToolsToProcess -ToolFilter $ToolFilter)) {
        $toolInfo = $ToolPaths[$toolName]
        $configPath = $toolInfo.configPath

        if (-not (Test-Path -LiteralPath $configPath)) {
            Write-Warning "跳过 $($toolInfo.displayName)：配置文件不存在 ($configPath)"
            continue
        }

        $toolOutDir = Join-Path $OutDir $toolName
        New-Item -ItemType Directory -Force -Path $toolOutDir | Out-Null

        $config = Read-JsonFile -Path $configPath
        $removed = Remove-PlaintextSecrets -Config $config
        $removedSecrets += $removed

        $destPath = Join-Path $toolOutDir 'providers.json'
        Write-Utf8NoBomJson -Path $destPath -Value $config
        Write-Output "已导出 $($toolInfo.displayName) 配置：$destPath"
        if ($removed -gt 0) {
            Write-Warning "  已从导出文件移除 $removed 个明文密钥字段。请在目标机器重新设置 API Key。"
        }
        $exported += $toolName

        $envVarsInfo = Get-EnvVarsInfo -Config $config
        if ($envVarsInfo.Count -gt 0) {
            $envInfoPath = Join-Path $toolOutDir 'env-vars-info.json'
            Write-Utf8NoBomJson -Path $envInfoPath -Value $envVarsInfo
            Write-Output "  环境变量信息：$envInfoPath"
        }
    }

    if ($exported.Count -eq 0) {
        Write-Warning '没有导出任何配置。'
        return
    }

    $readmePath = Join-Path $OutDir 'README.txt'
    $readmeContent = @"
Provider Profiles 备份
=====================
导出时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
导出工具：$($exported -join ', ')

使用方法：
1. 将整个目录复制到目标机器
2. 运行导入命令：
   ccp profiles import -InDir "$OutDir" -Tool all

安全说明：
- 导出文件默认不包含 profile 中的明文密钥字段：apiKey、token、key
- 如果原配置使用 apiKeyEnv / tokenEnv / keyEnv，请在目标机器手动设置对应环境变量
- 环境变量信息保存在各工具子目录的 env-vars-info.json 中，仅包含变量名和是否已设置，不包含变量值
- 本次导出移除明文密钥字段数量：$removedSecrets
"@
    Write-Utf8NoBomText -Path $readmePath -Text $readmeContent

    Write-Output ""
    Write-Output "导出完成！备份目录：$OutDir"

    if ($Compress) {
        $zipPath = "$OutDir.zip"
        if ((Test-Path -LiteralPath $zipPath) -and -not $Force) {
            Write-Warning "压缩文件已存在：$zipPath。使用 -Force 覆盖。"
            return
        }

        Compress-Archive -LiteralPath $OutDir -DestinationPath $zipPath -Force
        Write-Output "已压缩：$zipPath"
    }
}

function Import-Profiles {
    param(
        [string]$InDir,
        [string]$ToolFilter
    )

    if (-not $InDir) {
        throw "请指定导入目录：-InDir '路径'"
    }

    $expandedTempDir = $null
    if ($InDir.EndsWith('.zip', [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $InDir)) {
        $expandedTempDir = Join-Path ([System.IO.Path]::GetTempPath()) "provider-import-$([guid]::NewGuid().ToString('N'))"
        Expand-Archive -LiteralPath $InDir -DestinationPath $expandedTempDir -Force
        $InDir = $expandedTempDir
        Write-Output "已解压到：$expandedTempDir"
    }

    try {
        if (-not (Test-Path -LiteralPath $InDir)) {
            throw "导入目录不存在：$InDir"
        }

        $importRoot = Resolve-ImportRoot -Path $InDir
        $imported = @()

        foreach ($toolName in (Get-ToolsToProcess -ToolFilter $ToolFilter)) {
            $toolInfo = $ToolPaths[$toolName]
            $sourcePath = Join-Path $importRoot "$toolName\providers.json"

            if (-not (Test-Path -LiteralPath $sourcePath)) {
                $sourcePath = Join-Path $importRoot 'providers.json'
                if (-not (Test-Path -LiteralPath $sourcePath)) {
                    Write-Warning "跳过 $($toolInfo.displayName)：未找到配置文件"
                    continue
                }
            }

            $importConfig = Read-JsonFile -Path $sourcePath
            if (-not $importConfig.PSObject.Properties['profiles']) {
                throw "导入配置必须包含 profiles 对象：$sourcePath"
            }
            if (Test-ContainsPlaintextSecrets -Config $importConfig) {
                Write-Warning "导入文件包含明文密钥字段：$sourcePath。请确认备份来源可信。"
            }

            $configPath = $toolInfo.configPath
            $configDir = Split-Path -Parent $configPath
            New-Item -ItemType Directory -Force -Path $configDir | Out-Null

            if (Test-Path -LiteralPath $configPath) {
                $backupPath = "$configPath.backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
                Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
                Write-Output "已备份现有配置：$backupPath"
            }

            Copy-Item -LiteralPath $sourcePath -Destination $configPath -Force
            Write-Output "已导入 $($toolInfo.displayName) 配置：$configPath"
            $imported += $toolName

            $profileIds = @($importConfig.profiles.PSObject.Properties.Name)
            Write-Output "  包含配置：$($profileIds -join ', ')"

            foreach ($prop in @($importConfig.profiles.PSObject.Properties)) {
                $profile = $prop.Value
                foreach ($envField in @('apiKeyEnv', 'tokenEnv', 'keyEnv')) {
                    $envProp = $profile.PSObject.Properties[$envField]
                    if ($envProp -and $envProp.Value) {
                        if (-not (Test-EnvironmentVariableConfigured -Name "$($envProp.Value)")) {
                            Write-Warning "  环境变量 $($envProp.Value) 未设置（配置：$($prop.Name)）。请在目标机器手动设置。"
                        }
                    }
                }
            }
        }

        if ($imported.Count -eq 0) {
            Write-Warning '没有导入任何配置。请检查导入目录结构。'
            Write-Output ''
            Write-Output '期望的目录结构：'
            Write-Output '  <导入目录>/'
            Write-Output '    claude/providers.json'
            Write-Output '    codex/providers.json'
            return
        }

        Write-Output ''
        Write-Output "导入完成！已导入：$($imported -join ', ')"
        Write-Output ''
        Write-Output '建议运行以下命令同步快捷命令：'
        foreach ($toolName in $imported) {
            Write-Output "  $($ToolPaths[$toolName].prefix) sync"
        }
    }
    finally {
        if ($expandedTempDir -and (Test-Path -LiteralPath $expandedTempDir)) {
            Remove-Item -LiteralPath $expandedTempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function List-Profiles {
    param([string]$ToolFilter)

    foreach ($toolName in (Get-ToolsToProcess -ToolFilter $ToolFilter)) {
        $toolInfo = $ToolPaths[$toolName]
        $configPath = $toolInfo.configPath

        Write-Output ''
        Write-Output "=== $($toolInfo.displayName) ==="
        Write-Output "配置文件：$configPath"

        if (-not (Test-Path -LiteralPath $configPath)) {
            Write-Output '  (配置文件不存在)'
            continue
        }

        $config = Read-JsonFile -Path $configPath
        if (-not $config.PSObject.Properties['profiles'] -or -not $config.profiles) {
            Write-Output '  (无 profiles)'
            continue
        }

        foreach ($prop in @($config.profiles.PSObject.Properties)) {
            $profile = $prop.Value
            $displayName = if ($profile.PSObject.Properties['displayName'] -and $profile.displayName) { $profile.displayName } else { $prop.Name }
            $model = if ($profile.PSObject.Properties['model'] -and $profile.model) { $profile.model } else { '(默认)' }
            Write-Output "  [$($prop.Name)] $displayName - $model"
            $baseUrl = if ($profile.PSObject.Properties['baseUrl']) { $profile.baseUrl } else { '(未设置)' }
            Write-Output "    baseUrl: $baseUrl"
            if (Test-ContainsPlaintextSecrets -Config ([pscustomobject]@{ profiles = [pscustomobject]@{ current = $profile } })) {
                Write-Output '    明文密钥：已配置（未显示，建议迁移到 apiKeyEnv）'
            }
            foreach ($envField in @('apiKeyEnv', 'tokenEnv', 'keyEnv')) {
                $envProp = $profile.PSObject.Properties[$envField]
                if ($envProp -and $envProp.Value) {
                    $hasEnv = Test-EnvironmentVariableConfigured -Name "$($envProp.Value)"
                    Write-Output "    ${envField}: $($envProp.Value) ($(if ($hasEnv) { '已设置' } else { '未设置' }))"
                }
            }
        }
    }
}

switch ($Action) {
    'export' {
        Export-Profiles -OutDir $OutDir -ToolFilter $Tool -Compress:$Compress -Force:$Force
    }
    'import' {
        Import-Profiles -InDir $InDir -ToolFilter $Tool
    }
    'list' {
        List-Profiles -ToolFilter $Tool
    }
}
