#!/usr/bin/env pwsh
<#
.SYNOPSIS
    安装 Provider Profiles 工具集（Claude Code + Codex CLI）。
.DESCRIPTION
    部署核心模块、工具脚本和 Web 管理台到用户目录。
    生成 bin 快捷命令并同步供应商快捷方式。
#>
[CmdletBinding()]
param(
    [switch]$OverwriteConfig,
    [switch]$AddPath,
    [switch]$Configure,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# === Remote bootstrap mode ===
# 当通过 `iwr https://.../install.ps1 | iex` 执行时，脚本不在磁盘上：
# $PSCommandPath 为空、$MyInvocation.MyCommand.Path 也为空。
# 自动下载 main 分支 archive，解压后转发参数调用真正的 install.ps1。
$invocationPath = try { $MyInvocation.MyCommand.Path } catch { $null }
if ([string]::IsNullOrEmpty($PSCommandPath) -and [string]::IsNullOrEmpty($invocationPath)) {
    $bootstrapUrl = if ($env:CPS_BOOTSTRAP_URL) { $env:CPS_BOOTSTRAP_URL } else {
        'https://github.com/QianChenJun/Claude-Code-Provider/archive/refs/heads/main.zip'
    }
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "cps-bootstrap-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $zipPath = Join-Path $tempDir 'source.zip'
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

    Write-Output "[远程引导] 下载源码：$bootstrapUrl"
    Invoke-WebRequest -Uri $bootstrapUrl -OutFile $zipPath -UseBasicParsing

    Write-Output "[远程引导] 解压到：$tempDir"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tempDir -Force
    Remove-Item -LiteralPath $zipPath -Force

    # archive 解压后是 <repo>-main/ 目录，取第一个子目录
    $extracted = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
    if (-not $extracted) { throw "解压后未找到源码目录：$tempDir" }
    $kitInstaller = Join-Path $extracted.FullName 'Claude-Provider-Profiles-Kit\install.ps1'
    if (-not (Test-Path -LiteralPath $kitInstaller)) {
        throw "解压后未找到 install.ps1：$kitInstaller"
    }

    # 转发命名开关参数（顺序与 param() 一致）
    $bootArgs = @{}
    if ($OverwriteConfig) { $bootArgs.OverwriteConfig = $true }
    if ($AddPath)         { $bootArgs.AddPath         = $true }
    if ($Configure)       { $bootArgs.Configure       = $true }
    if ($DryRun)          { $bootArgs.DryRun          = $true }

    Write-Output "[远程引导] 调用本地 install.ps1（$kitInstaller）"
    & $kitInstaller @bootArgs
    return
}

$kitRoot    = Split-Path -Parent $MyInvocation.MyCommand.Path
# Source: try Kit/src first (zip distribution), fall back to repo root src/ (development)
$sourceRoot = Join-Path $kitRoot 'src'
if (-not (Test-Path -LiteralPath $sourceRoot)) {
    $sourceRoot = Join-Path (Split-Path -Parent $kitRoot) 'src'
}
if (-not (Test-Path -LiteralPath $sourceRoot)) {
    throw "找不到 src 目录。请从项目根目录或解压后的 Kit 目录运行安装脚本。"
}
# === Target directories ===
$claudeRoot = Join-Path $env:USERPROFILE '.claude\provider-profiles'
$claudeBin  = Join-Path $env:USERPROFILE '.claude\bin'
$codexRoot  = Join-Path $env:USERPROFILE '.codex\provider-profiles'
$codexBin   = Join-Path $env:USERPROFILE '.codex\bin'

# === Config templates ===
$claudeExampleCfg = Join-Path $kitRoot 'providers.example.json'
$codexExampleCfg  = Join-Path $kitRoot 'codex-providers.example.json'

# Prerequisites
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Warning "未找到 claude 命令。请先安装 Claude Code。"
}
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    Write-Warning "未找到 codex 命令。请先安装 Codex CLI。"
}

function Copy-RequiredFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "缺少安装文件：$Source"
    }
    if ($DryRun) {
        Write-Output "DRY-RUN 复制：$Source -> $Destination"
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Deploy-SharedFiles {
    param([Parameter(Mandatory)][string]$TargetRoot)

    $files = @(
        @{ Source = 'core\ProviderCore.psm1';      Destination = 'src\core\ProviderCore.psm1' },
        @{ Source = 'tools\Import-Core.ps1';       Destination = 'src\tools\Import-Core.ps1' },
        @{ Source = 'tools\Invoke-Provider.ps1';   Destination = 'src\tools\Invoke-Provider.ps1' },
        @{ Source = 'tools\Sync-Shortcuts.ps1';    Destination = 'src\tools\Sync-Shortcuts.ps1' },
        @{ Source = 'tools\Manage-ProviderUI.ps1'; Destination = 'src\tools\Manage-ProviderUI.ps1' },
        @{ Source = 'tools\Manage-ProviderProfiles.ps1'; Destination = 'src\tools\Manage-ProviderProfiles.ps1' },
        @{ Source = 'server.mjs';                  Destination = 'server.mjs' },
        @{ Source = 'web\index.html';              Destination = 'web\index.html' },
        @{ Source = 'web\app.js';                  Destination = 'web\app.js' },
        @{ Source = 'web\styles.css';              Destination = 'web\styles.css' }
    )

    foreach ($file in $files) {
        Copy-RequiredFile `
            -Source (Join-Path $sourceRoot $file.Source) `
            -Destination (Join-Path $TargetRoot $file.Destination)
    }
}

function Deploy-ToolFiles {
    param(
        [Parameter(Mandatory)][string]$ToolName,
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][string[]]$Files
    )

    foreach ($file in $Files) {
        Copy-RequiredFile `
            -Source (Join-Path $sourceRoot "tools\$ToolName\$file") `
            -Destination (Join-Path $TargetRoot "src\tools\$ToolName\$file")
    }
}

function Initialize-ConfigFile {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$TemplatePath,
        [string]$LegacyPath
    )

    if ($DryRun) {
        if ($OverwriteConfig) {
            if (-not (Test-Path -LiteralPath $TemplatePath)) {
                throw "缺少安装文件：$TemplatePath"
            }
            Write-Output "DRY-RUN 将覆盖 $Name 配置：$TargetPath"
        } elseif (Test-Path -LiteralPath $TargetPath) {
            Write-Output "DRY-RUN 将保留已有 $Name 配置：$TargetPath"
        } elseif ($LegacyPath -and (Test-Path -LiteralPath $LegacyPath)) {
            Write-Output "DRY-RUN 将从旧目录迁移 $Name 配置：$LegacyPath -> $TargetPath"
        } else {
            if (-not (Test-Path -LiteralPath $TemplatePath)) {
                throw "缺少安装文件：$TemplatePath"
            }
            Write-Output "DRY-RUN 将写入 $Name 配置模板：$TargetPath"
        }
        return
    }

    if ($OverwriteConfig) {
        Copy-RequiredFile -Source $TemplatePath -Destination $TargetPath
        Write-Output "已写入 $Name 配置：$TargetPath"
        return
    }

    if (Test-Path -LiteralPath $TargetPath) {
        Write-Output "保留已有 $Name 配置"
        return
    }

    if ($LegacyPath -and (Test-Path -LiteralPath $LegacyPath)) {
        Copy-RequiredFile -Source $LegacyPath -Destination $TargetPath
        Write-Output "已从旧目录迁移 $Name 配置"
        return
    }

    Copy-RequiredFile -Source $TemplatePath -Destination $TargetPath
    Write-Output "已写入 $Name 配置模板"
}

function Ensure-UserPathItem {
    param([Parameter(Mandatory)][string]$PathItem, [switch]$ShouldAdd)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $items = if ($userPath) { $userPath -split ';' | Where-Object { $_ } } else { @() }
    $exists = $items | Where-Object { $_.TrimEnd('\') -ieq $PathItem.TrimEnd('\') }
    if ($exists) { return }
    if ($DryRun -and $ShouldAdd) {
        Write-Output "DRY-RUN 将加入用户 PATH：$PathItem"
        return
    }
    if ($ShouldAdd) {
        [Environment]::SetEnvironmentVariable('Path', (($items + $PathItem) -join ';'), 'User')
        Write-Output "已加入用户 PATH：$PathItem"
    } else {
        Write-Warning "快捷命令目录不在 PATH 中：$PathItem"
    }
}

function Invoke-PostInstallConfigure {
    $choice = (Read-Host "立即配置哪个工具？[B]两个 / [C]Claude / [D]Codex / [S]跳过（默认 B）").Trim()
    if (-not $choice) { $choice = 'B' }

    if ($choice -match '^(s|skip|跳过)$') { return }

    if ($choice -match '^(b|both|两个)$' -or $choice -match '^(c|claude)$') {
        & (Join-Path $claudeRoot 'src\tools\claude\Invoke-ClaudeProvider.ps1') setup
    }

    if ($choice -match '^(b|both|两个)$' -or $choice -match '^(d|codex)$') {
        & (Join-Path $codexRoot 'src\tools\codex\Invoke-CodexProvider.ps1') setup
    }
}

# === Create target directories ===
$targetDirs = @(
    (Join-Path $claudeRoot 'src\core'),
    (Join-Path $claudeRoot 'src\tools\claude'),
    (Join-Path $claudeRoot 'web'),
    $claudeBin,
    (Join-Path $codexRoot 'src\core'),
    (Join-Path $codexRoot 'src\tools\codex'),
    (Join-Path $codexRoot 'web'),
    $codexBin
)
foreach ($dir in $targetDirs) {
    if ($DryRun) {
        Write-Output "DRY-RUN 创建目录：$dir"
    } else {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

Write-Output "=== 部署核心模块 ==="

foreach ($target in @($claudeRoot, $codexRoot)) {
    Deploy-SharedFiles -TargetRoot $target
}
Write-Output "已部署核心模块"

Write-Output "=== 部署 Claude Code 工具 ==="
Deploy-ToolFiles -ToolName 'claude' -TargetRoot $claudeRoot -Files @(
    'Invoke-ClaudeProvider.ps1',
    'Sync-ClaudeShortcuts.ps1',
    'Manage-ClaudeUI.ps1'
)

Write-Output "=== 部署 Codex CLI 工具 ==="
Deploy-ToolFiles -ToolName 'codex' -TargetRoot $codexRoot -Files @(
    'Invoke-CodexProvider.ps1',
    'Sync-CodexShortcuts.ps1',
    'Manage-CodexUI.ps1'
)

Write-Output "=== 初始化配置文件 ==="

$claudeConfigPath = Join-Path $claudeRoot 'providers.json'
Initialize-ConfigFile `
    -Name 'Claude' `
    -TargetPath $claudeConfigPath `
    -TemplatePath $claudeExampleCfg `
    -LegacyPath (Join-Path $env:USERPROFILE '.cc-switch\claude-profiles\providers.json')

$codexConfigPath = Join-Path $codexRoot 'providers.json'
Initialize-ConfigFile `
    -Name 'Codex' `
    -TargetPath $codexConfigPath `
    -TemplatePath $codexExampleCfg

Write-Output "=== 生成快捷命令 ==="

if ($DryRun) {
    Write-Output "DRY-RUN 将生成 Claude 快捷命令：$claudeBin"
    Write-Output "DRY-RUN 将生成 Codex 快捷命令：$codexBin"
} else {
    # Generate bin shims for Claude
    & (Join-Path $claudeRoot 'src\tools\claude\Sync-ClaudeShortcuts.ps1') | Out-Host

    # Generate bin shims for Codex
    & (Join-Path $codexRoot 'src\tools\codex\Sync-CodexShortcuts.ps1') | Out-Host
}

Write-Output "=== PATH 管理 ==="
Ensure-UserPathItem -PathItem $claudeBin -ShouldAdd:$AddPath
Ensure-UserPathItem -PathItem $codexBin  -ShouldAdd:$AddPath

Write-Output ""
Write-Output "========================================="
if ($DryRun) {
    Write-Output " 预检完成，未写入任何文件"
} else {
    Write-Output " 安装完成"
}
Write-Output "========================================="
Write-Output ""
Write-Output "Claude Code (ccp):"
Write-Output "  配置文件：$claudeConfigPath"
Write-Output "  快捷命令：$claudeBin"
Write-Output "  使用：ccp / ccp setup / ccp mi / ccp list / ccp manager / ccp profiles"
Write-Output ""
Write-Output "Codex CLI (cdp):"
Write-Output "  配置文件：$codexConfigPath"
Write-Output "  快捷命令：$codexBin"
Write-Output "  使用：cdp / cdp setup / cdp ds / cdp list / cdp manager / cdp profiles"
Write-Output ""

if (-not $AddPath) {
    Write-Warning "如需自动加入用户级 PATH，请重新执行：.\install.ps1 -AddPath"
} else {
    Write-Output "已修改用户级 PATH，仅新增 .claude\bin / .codex\bin；推荐优先使用 ccp <profile> / cdp <profile> 子命令。"
    Write-Output "请重新打开 PowerShell / Windows Terminal 后使用快捷命令。"
}

if ($Configure -and $DryRun) {
    Write-Output ""
    Write-Output "DRY-RUN 已跳过配置向导"
} elseif ($Configure) {
    Write-Output ""
    Write-Output "=== 配置向导 ==="
    Invoke-PostInstallConfigure
}
