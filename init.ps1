#!/usr/bin/env pwsh
<#
.SYNOPSIS
    AI CLI Switcher — 快速入口脚本。
.DESCRIPTION
    在开发环境中直接使用，无需运行 install.ps1。
    提供同步快捷命令、启动 Web 管理台、查看状态等功能。
.PARAMETER Action
    sync    — 为所有已注册工具生成快捷命令
    setup   — 交互式新增或更新供应商配置
    web     — 启动统一 Web 管理台
    list    — 列出所有已注册工具及其配置
    check   — 检查环境（claude、codex、node 是否可用）
    help    — 显示帮助
.EXAMPLE
    .\init.ps1              # 默认：显示状态
    .\init.ps1 sync         # 同步快捷命令
    .\init.ps1 setup        # 配置向导
    .\init.ps1 web          # 启动 Web 管理台
    .\init.ps1 check        # 检查环境
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('sync', 'setup', 'web', 'list', 'check', 'help', '')]
    [string]$Action = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import core module
. (Join-Path $repoRoot 'src\tools\Import-Core.ps1')
Import-ProviderCore

function Write-Header {
    param([string]$Text)
    Write-Output ""
    Write-Output "========================================="
    Write-Output " $Text"
    Write-Output "========================================="
    Write-Output ""
}

function Test-CommandExists {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

switch ($Action) {
    'check' {
        Write-Header "环境检查"

        $checks = @(
            @{ Name = 'claude'; Desc = 'Claude Code CLI'; Required = $false },
            @{ Name = 'codex';  Desc = 'Codex CLI';       Required = $false },
            @{ Name = 'node';   Desc = 'Node.js (Web UI)'; Required = $false },
            @{ Name = 'pwsh';   Desc = 'PowerShell 7+';   Required = $false }
        )

        foreach ($check in $checks) {
            $exists = Test-CommandExists $check.Name
            $icon = if ($exists) { '[OK]' } else { '[--]' }
            $version = ''
            if ($exists) {
                try {
                    $v = & $check.Name --version 2>&1 | Select-Object -First 1
                    $version = " ($v)"
                } catch {}
            }
            $status = if (-not $exists -and $check.Required) { ' ← 需要安装' } else { '' }
            Write-Output "  $icon $($check.Desc)$version$status"
        }

        Write-Output ""
        Write-Output "配置目录："
        $claudeRoot = Join-Path $env:USERPROFILE '.claude\provider-profiles'
        $codexRoot  = Join-Path $env:USERPROFILE '.codex\provider-profiles'

        foreach ($dir in @($claudeRoot, $codexRoot)) {
            $exists = Test-Path -LiteralPath (Join-Path $dir 'providers.json')
            $icon = if ($exists) { '[OK]' } else { '[--]' }
            Write-Output "  $icon $dir\providers.json"
        }
    }

    'list' {
        Write-Header "已注册工具"

        $tools = Get-ProviderTools
        foreach ($entry in $tools.GetEnumerator() | Sort-Object Name) {
            $t = $entry.Value
            $configExists = Test-Path -LiteralPath $t.configPath
            $configIcon = if ($configExists) { '[OK]' } else { '[--]' }
            Write-Output "  $($t.commandPrefix)  $($t.displayName.PadRight(16))  配置: $configIcon $($t.configPath)"
        }

        Write-Output ""
        Write-Output "运行 'init.ps1 sync' 生成快捷命令。"
    }

    'sync' {
        Write-Header "同步快捷命令"

        $tools = Get-ProviderTools
        foreach ($entry in $tools.GetEnumerator() | Sort-Object Name) {
            $name = $entry.Key
            $t = $entry.Value
            if (-not (Test-Path -LiteralPath $t.configPath)) {
                Write-Warning "跳过 $($t.displayName)：配置文件不存在 ($($t.configPath))"
                continue
            }
            Write-Output "--- $($t.displayName) ---"
            Sync-ToolShortcuts -ToolName $name
            Write-Output ""
        }
    }

    'setup' {
        Write-Header "配置向导"

        $tools = Get-ProviderTools
        foreach ($entry in $tools.GetEnumerator() | Sort-Object Name) {
            $t = $entry.Value
            Write-Output "  $($t.commandPrefix)  $($t.displayName)"
        }

        Write-Output ""
        $choice = (Read-Host "选择工具：[B]两个 / [C]Claude / [D]Codex / [Q]退出（默认 B）").Trim()
        if (-not $choice) { $choice = 'B' }
        if ($choice -match '^(q|quit|exit|退出)$') { return }

        if ($choice -match '^(b|both|两个)$' -or $choice -match '^(c|claude|ccp)$') {
            Invoke-ProviderSetup -ToolName 'claude'
        }

        if ($choice -match '^(b|both|两个)$' -or $choice -match '^(d|codex|cdp)$') {
            Invoke-ProviderSetup -ToolName 'codex'
        }
    }

    'web' {
        $serverPath = Join-Path $repoRoot 'src\server.mjs'
        if (-not (Test-Path -LiteralPath $serverPath)) {
            throw "找不到 server.mjs：$serverPath"
        }
        if (-not (Test-CommandExists 'node')) {
            throw "未找到 node。Web 管理台需要 Node.js 18+。"
        }

        Write-Header "启动 Web 管理台"
        Start-Process "http://127.0.0.1:15722/" | Out-Null
        node $serverPath --port 15722
    }

    'help' {
        Write-Header "AI CLI Switcher — 帮助"
        Write-Output "用法：.\init.ps1 <command>"
        Write-Output ""
        Write-Output "  check   检查环境依赖"
        Write-Output "  list    列出已注册工具"
        Write-Output "  setup   交互式新增或更新供应商配置"
        Write-Output "  sync    同步快捷命令到 bin 目录"
        Write-Output "  web     启动统一 Web 管理台"
        Write-Output "  help    显示此帮助"
        Write-Output ""
        Write-Output "快捷命令（同步后可用）："
        Write-Output "  ccp / ccp setup / ccp mi / ccp list / ccp manager"
        Write-Output "  cdp / cdp setup / cdp ds / cdp list / cdp manager"
        Write-Output ""
        Write-Output "详细文档：README.md"
    }

    default {
        Write-Header "AI CLI Switcher"
        $tools = Get-ProviderTools
        Write-Output "已注册工具："
        foreach ($entry in $tools.GetEnumerator() | Sort-Object Name) {
            $t = $entry.Value
            Write-Output "  $($t.commandPrefix)  $($t.displayName)"
        }
        Write-Output ""
        Write-Output "快速命令："
        Write-Output "  .\init.ps1 check   检查环境"
        Write-Output "  .\init.ps1 setup   配置向导"
        Write-Output "  .\init.ps1 sync    同步快捷命令"
        Write-Output "  .\init.ps1 web     启动 Web 管理台"
        Write-Output "  .\init.ps1 help    查看完整帮助"
    }
}
