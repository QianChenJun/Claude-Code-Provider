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
    [switch]$AddPath
)

$ErrorActionPreference = 'Stop'

$kitRoot    = Split-Path -Parent $MyInvocation.MyCommand.Path
# Source: try Kit/src first (zip distribution), fall back to repo root src/ (development)
$sourceRoot = Join-Path $kitRoot 'src'
if (-not (Test-Path -LiteralPath $sourceRoot)) {
    $sourceRoot = Join-Path (Split-Path -Parent $kitRoot) 'src'
}
if (-not (Test-Path -LiteralPath $sourceRoot)) {
    throw "找不到 src 目录。请从项目根目录或解压后的 Kit 目录运行安装脚本。"
}
$encoding   = [System.Text.UTF8Encoding]::new($false)

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

# === Create target directories ===
foreach ($dir in @(
    (Join-Path $claudeRoot 'src\core'),
    (Join-Path $claudeRoot 'src\tools\claude'),
    (Join-Path $claudeRoot 'web'),
    $claudeBin,
    (Join-Path $codexRoot 'src\core'),
    (Join-Path $codexRoot 'src\tools\codex'),
    (Join-Path $codexRoot 'web'),
    $codexBin
)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

Write-Output "=== 部署核心模块 ==="

# Deploy shared core module to both targets
foreach ($target in @($claudeRoot, $codexRoot)) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'core\ProviderCore.psm1') `
              -Destination (Join-Path $target 'src\core\ProviderCore.psm1') -Force
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools\Import-Core.ps1') `
              -Destination (Join-Path $target 'src\tools\Import-Core.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools\Invoke-Provider.ps1') `
              -Destination (Join-Path $target 'src\tools\Invoke-Provider.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools\Sync-Shortcuts.ps1') `
              -Destination (Join-Path $target 'src\tools\Sync-Shortcuts.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools\Manage-ProviderUI.ps1') `
              -Destination (Join-Path $target 'src\tools\Manage-ProviderUI.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'server.mjs') `
              -Destination (Join-Path $target 'server.mjs') -Force
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'web\index.html') `
              -Destination (Join-Path $target 'web\index.html') -Force
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'web\app.js') `
              -Destination (Join-Path $target 'web\app.js') -Force
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'web\styles.css') `
              -Destination (Join-Path $target 'web\styles.css') -Force
}
Write-Output "已部署核心模块"

Write-Output "=== 部署 Claude Code 工具 ==="
Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools\claude\Invoke-ClaudeProvider.ps1') `
          -Destination (Join-Path $claudeRoot 'src\tools\claude\Invoke-ClaudeProvider.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools\claude\Sync-ClaudeShortcuts.ps1') `
          -Destination (Join-Path $claudeRoot 'src\tools\claude\Sync-ClaudeShortcuts.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools\claude\Manage-ClaudeUI.ps1') `
          -Destination (Join-Path $claudeRoot 'src\tools\claude\Manage-ClaudeUI.ps1') -Force

Write-Output "=== 部署 Codex CLI 工具 ==="
Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools\codex\Invoke-CodexProvider.ps1') `
          -Destination (Join-Path $codexRoot 'src\tools\codex\Invoke-CodexProvider.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools\codex\Sync-CodexShortcuts.ps1') `
          -Destination (Join-Path $codexRoot 'src\tools\codex\Sync-CodexShortcuts.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools\codex\Manage-CodexUI.ps1') `
          -Destination (Join-Path $codexRoot 'src\tools\codex\Manage-CodexUI.ps1') -Force

Write-Output "=== 初始化配置文件 ==="

# Claude config
$claudeConfigPath = Join-Path $claudeRoot 'providers.json'
if ($OverwriteConfig) {
    Copy-Item -LiteralPath $claudeExampleCfg -Destination $claudeConfigPath -Force
    Write-Output "已写入 Claude 配置：$claudeConfigPath"
} elseif (Test-Path -LiteralPath $claudeConfigPath) {
    Write-Output "保留已有 Claude 配置"
} else {
    # Try legacy migration
    $legacyPath = Join-Path $env:USERPROFILE '.cc-switch\claude-profiles\providers.json'
    if (Test-Path -LiteralPath $legacyPath) {
        Copy-Item -LiteralPath $legacyPath -Destination $claudeConfigPath -Force
        Write-Output "已从旧目录迁移 Claude 配置"
    } else {
        Copy-Item -LiteralPath $claudeExampleCfg -Destination $claudeConfigPath -Force
        Write-Output "已写入 Claude 配置模板"
    }
}

# Codex config
$codexConfigPath = Join-Path $codexRoot 'providers.json'
if ($OverwriteConfig) {
    Copy-Item -LiteralPath $codexExampleCfg -Destination $codexConfigPath -Force
    Write-Output "已写入 Codex 配置：$codexConfigPath"
} elseif (Test-Path -LiteralPath $codexConfigPath) {
    Write-Output "保留已有 Codex 配置"
} else {
    Copy-Item -LiteralPath $codexExampleCfg -Destination $codexConfigPath -Force
    Write-Output "已写入 Codex 配置模板"
}

Write-Output "=== 生成快捷命令 ==="

# Generate bin shims for Claude
& (Join-Path $claudeRoot 'src\tools\claude\Sync-ClaudeShortcuts.ps1') | Out-Host

# Generate bin shims for Codex
& (Join-Path $codexRoot 'src\tools\codex\Sync-CodexShortcuts.ps1') | Out-Host

Write-Output "=== PATH 管理 ==="

function Ensure-UserPathItem {
    param([Parameter(Mandatory)][string]$PathItem, [switch]$ShouldAdd)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $items = if ($userPath) { $userPath -split ';' | Where-Object { $_ } } else { @() }
    $exists = $items | Where-Object { $_.TrimEnd('\') -ieq $PathItem.TrimEnd('\') }
    if ($exists) { return }
    if ($ShouldAdd) {
        [Environment]::SetEnvironmentVariable('Path', (($items + $PathItem) -join ';'), 'User')
        Write-Output "已加入用户 PATH：$PathItem"
    } else {
        Write-Warning "快捷命令目录不在 PATH 中：$PathItem"
    }
}

Ensure-UserPathItem -PathItem $claudeBin -ShouldAdd:$AddPath
Ensure-UserPathItem -PathItem $codexBin  -ShouldAdd:$AddPath

Write-Output ""
Write-Output "========================================="
Write-Output " 安装完成"
Write-Output "========================================="
Write-Output ""
Write-Output "Claude Code (ccp):"
Write-Output "  配置文件：$claudeConfigPath"
Write-Output "  快捷命令：$claudeBin"
Write-Output "  使用：ccp / ccp-mi / ccp-ds / ccp-list / ccp-manager"
Write-Output ""
Write-Output "Codex CLI (cdp):"
Write-Output "  配置文件：$codexConfigPath"
Write-Output "  快捷命令：$codexBin"
Write-Output "  使用：cdp / cdp-mi / cdp-ds / cdp-list / cdp-manager"
Write-Output ""

if (-not $AddPath) {
    Write-Warning "如需自动加入 PATH，请重新执行：.\install.ps1 -AddPath"
} else {
    Write-Output "请重新打开 PowerShell / Windows Terminal 后使用快捷命令。"
}