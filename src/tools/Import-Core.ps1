$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Bootstrap helper — 定位并导入 ProviderCore.psm1。
.DESCRIPTION
    所有工具脚本通过 . Import-Core.ps1 来加载核心模块。
    按以下顺序查找 ProviderCore.psm1：
    1. 相对于当前脚本目录（部署场景：~/.xxx/bin -> ~/.xxx/provider-profiles/src/core/）
    2. 向上遍历目录树（仓库开发场景）
    3. 环境变量 PROVIDER_CORE_MODULE
#>

function Import-ProviderCore {
    [CmdletBinding()]
    param()

    $corePath = $null

    # Strategy 1: One level up from script directory
    $candidate = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\core\ProviderCore.psm1'
    if (Test-Path -LiteralPath $candidate) {
        $corePath = [System.IO.Path]::GetFullPath($candidate)
    }

    # Strategy 2: Walk up from script directory
    if (-not $corePath) {
        $dir = Split-Path -Parent $PSScriptRoot
        for ($i = 0; $i -lt 5; $i++) {
            $candidate = Join-Path $dir 'src\core\ProviderCore.psm1'
            if (Test-Path -LiteralPath $candidate) {
                $corePath = [System.IO.Path]::GetFullPath($candidate)
                break
            }
            $parent = Split-Path -Parent $dir
            if (-not $parent -or $parent -eq $dir) { break }
            $dir = $parent
        }
    }

    # Strategy 3: Environment variable
    if (-not $corePath -and $env:PROVIDER_CORE_MODULE) {
        if (Test-Path -LiteralPath $env:PROVIDER_CORE_MODULE) {
            $corePath = [System.IO.Path]::GetFullPath($env:PROVIDER_CORE_MODULE)
        }
    }

    if (-not $corePath) {
        throw "找不到 ProviderCore.psm1。请设置环境变量 PROVIDER_CORE_MODULE 指向模块路径。"
    }

    Import-Module $corePath -Force -DisableNameChecking
}